#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
    sudo -E "$0" "$@"
    exit $?
fi

source "common.sh"

# Ensure that pixz or xz is installed
{ which pixz > /dev/null 2>&1 || which xz > /dev/null 2>&1; } || {
  log_err "pixz/xz not found"
  exit 1
}

# Settings
IMAGE_NAME="FedoraWorkstation"
RAW_IMAGE=$(realpath "./cache/Fedora-Workstation.raw")

# Begin script

log "Start creating image: $IMAGE_NAME"

# Preparing generic image
if [ ! -f "$RAW_IMAGE" ]; then
  log "Downloading generic image"
  wget "https://fedora.mirrorservice.org/fedora/linux/releases/40/Workstation/aarch64/images/Fedora-Workstation-40-1.14.aarch64.raw.xz" -O "$RAW_IMAGE".xz
  log "Extracting generic image"
  if which pixz > /dev/null 2>&1; then
    pixz -d "$RAW_IMAGE".xz
  elif which xz > /dev/null 2>&1; then
    xz -d "$RAW_IMAGE".xz
  fi
fi

# +++ Extarct rootfs
log "Mounting generic image"
loop=$(losetup -Pf --show "$RAW_IMAGE")
raw_mnt=$(mktemp --tmpdir=./tmp -d )
mount "${loop}p3" "$raw_mnt"

log "Creating system image"
create_image "$IMAGE_NAME" 30

rootdir=$(mount_image "$IMAGE_NAME")

log "Syncing system"
rsync -a --info=progress2 --info=name0 "$raw_mnt/root/"* "$rootdir/" 

log "Unmounting generic image"
umount "$raw_mnt"
rm -d "$raw_mnt"
losetup -d "$loop"
# ---

# Set hostname
log "Setting hostname"
echo "xiaomi-nabu" > "$rootdir/etc/hostname"

prepare_chroot "$rootdir"

# Creaate mountpoins
mkdir -p "$rootdir/tmp/"

# Remove some junk
log "Removing default kernel and settings"
rm -rf "$rootdir/usr/lib/kernel/install.d/10-devicetree.instal"
chroot "$rootdir" /usr/bin/bash -c "rpm --noscripts -e gnome-initial-setup qcom-firmware atheros-firmware brcmfmac-firmware amd-ucode-firmware kernel-core nvidia-gpu-firmware kernel kernel-modules kernel-modules-core intel-audio-firmware cirrus-audio-firmware nvidia-gpu-firmware linux-firmware linux-firmware-whence intel-gpu-firmware amd-gpu-firmware libertas-firmware mt7xxx-firmware nxpwireless-firmware realtek-firmware tiwilink-firmware"
chroot "$rootdir" rm -rf "/boot/*"

# Install nabu specific packages
log "Installing nabu kernel, modules, firmwares and userspace daemons"
cp ./packages/*.rpm "$rootdir/tmp/"
chroot "$rootdir" /usr/bin/bash -c "rpm -i /tmp/*.rpm"
chroot "$rootdir" /usr/bin/bash -c "rm /tmp/*.rpm"


# Enable userspace daemons
log "Enabling userspace daemons"
chroot "$rootdir" systemctl enable qrtr-ns pd-mapper tqftpserv rmtfs

log "Generating fstab"
gen_fstab "$rootdir"

# Add %wheel to sudoers
log "Adding %wheel to sudoers"
cp ./drop/00_image_builder "$rootdir/etc/sudoers.d/00_image_builder"


# +++ Rotate gdm
log "Configuring gdm and gnome"
mkdir -p "$rootdir/etc/skel/.config"
echo '<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>2</scale>
      <primary>yes</primary>
      <transform>
        <rotation>right</rotation>
        <flipped>no</flipped>
      </transform>
      <monitor>
        <monitorspec>
          <connector>DSI-1</connector>
          <vendor>unknown</vendor>
          <product>unknown</product>
          <serial>unknown</serial>
        </monitorspec>
        <mode>
          <width>1600</width>
          <height>2560</height>
          <rate>104.000</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
' > "$rootdir/etc/skel/.config/monitors.xml"
chroot "$rootdir" bash -c 'cp /etc/skel/.config/monitors.xml ~gdm/.config/'
chroot "$rootdir" bash -c 'chown gdm: ~gdm/.config/'
# ---

# Finish image
log "Finishing image"
detach_chroot "$rootdir"
umount_image "$rootdir"
trim_image "$IMAGE_NAME"

log "Stop creating image: $IMAGE_NAME"

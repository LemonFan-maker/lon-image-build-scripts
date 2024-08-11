#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
  sudo -E "$0" "$@"
  exit $?
fi

source common.sh

# Ensure that bsdtar is installed
which bsdtar > /dev/null 2>&1 || {
  log_err "bsdtar not found"
  exit 1
}

IMAGE_NAME="ArchLinuxArmGnome"

# Begin script

log "Start creating image: $IMAGE_NAME"
create_image "$IMAGE_NAME"
rootdir="$(mount_image "$IMAGE_NAME")"

# Prepare rootfs
if [ ! -f ./cache/ArchLinuxARM-aarch64-latest.tar.gz ]; then 
  log "Downloading rootfs tarball"
  wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz -O ./cache/ArchLinuxARM-aarch64-latest.tar.gz
fi

log "Extracting rootfs tarball"
bsdtar -xpf ./cache/ArchLinuxARM-aarch64-latest.tar.gz -C "$rootdir"

prepare_chroot "$rootdir"

# Setup inet
log "Setting up chroot"
mv "$rootdir/etc/resolv.conf" "$rootdir/etc/resolv.conf.1" 
echo "nameserver 1.1.1.1" > "$rootdir/etc/resolv.conf"
echo "xiaomi-nabu" > "$rootdir/etc/hostname"

# Remove some junk
log "Removing default kernel and settings"
chroot "$rootdir" userdel -r alarm
chroot "$rootdir" pacman -R linux-aarch64 linux-firmware --noconfirm

# Install minimal desktop environment
log "Populating pacman key store"
chroot "$rootdir" pacman-key --init
chroot "$rootdir" pacman-key --populate archlinuxarm
log "Updating system and installing needed packages"
chroot "$rootdir" sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
chroot "$rootdir" pacman -Syu sudo gdm gnome-menus gnome-backgrounds gnome-control-center gnome-keyring xdg-user-dirs-gtk nautilus xdg-desktop-portal-gnome gnome-console bluez bluez-utils vulkan-freedreno networkmanager --noconfirm

# Install nabu specific packages
log "Installing nabu kernel, modules, firmwares and userspace daemons"
cp ./packages/*.zst "$rootdir/opt/"
chroot "$rootdir" bash -c "pacman -U /opt/*.zst --noconfirm"
rm "$rootdir"/opt/*.zst

# Enable userspace daemons
log "Enabling userspace daemons"
chroot "$rootdir" systemctl enable qrtr-ns pd-mapper tqftpserv rmtfs gdm bluetooth NetworkManager

# Clean pacman cache
log "Cleaning pacman cache"
yes | chroot "$rootdir" pacman -Scc

log "Generating fstab"
gen_fstab "$rootdir"

# Add %wheel to sudoers
log "Adding %wheel to sudoers"
echo "%wheel ALL=(ALL:ALL) ALL" > "$rootdir/etc/sudoers.d/00_image_builder"

# Set default timezone
log "Setting default timezone"
chroot "$rootdir" timedatectl set-timezone Europe/Moscow

# Generate en_US locale
log "Generating en_US locale"
sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" "$rootdir/etc/locale.gen"
chroot "$rootdir" locale-gen
echo "LANG=en_US.UTF-8" > "$rootdir/etc/locale.conf"

# +++ Rotate user desktop and gdm
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

# Restore resolv.conf symlink
log "Restoring resolv.conf symlink"
mv "$rootdir/etc/resolv.conf.1" "$rootdir/etc/resolv.conf"
rm "$rootdir"/.* > /dev/null 2>&1

# Finish image
log "Finishing image"
detach_chroot "$rootdir"
umount_image "$rootdir"
trim_image "$IMAGE_NAME"

log "Stop creating image: $IMAGE_NAME"

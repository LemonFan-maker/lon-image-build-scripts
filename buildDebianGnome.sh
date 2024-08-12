#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
  sudo -E "$0" "$@"
  exit $?
fi

source common.sh

# Ensure that debootstarp is installed
which debootstrap > /dev/null 2>&1 || {
  log_err "debootstrap not found"
  exit 1
}

# Settings
VERSION="bookworm"
IMAGE_NAME="Debian12Gnome"

# Begin script

log "Start creating image: $IMAGE_NAME"
create_image "$IMAGE_NAME"
rootdir="$(mount_image "$IMAGE_NAME")"

# Fetch base system
log "Fetching base system"
debootstrap --arch arm64 --exclude=pulseaudio "$VERSION" "$rootdir" || {
  detach_chroot "$rootdir"
  umount_image "$rootdir"
  rm "$IMAGE_NAME"
  rm -rf "$rootdir"
  exit 1
}

prepare_chroot "$rootdir"
export DEBIAN_FRONTEND=noninteractive

# Setup inet
log "Setting up chroot"
echo "nameserver 1.1.1.1" > "$rootdir/etc/resolv.conf"
echo "xiaomi-nabu" > "$rootdir/etc/hostname"
echo "127.0.0.1 localhost
127.0.1.1 xiaomi-nabu" > "$rootdir/etc/hosts"

# Update system and install desktop
log "Updating system and installing needed packages"
chroot "$rootdir" apt update
chroot "$rootdir" apt upgrade -y
chroot "$rootdir" apt install -y gnome-core bash-completion sudo ssh nano systemd-zram-generator

# Install nabu specific packages
log "Installing nabu kernel, modules, firmwares and userspace daemons"
cp ./packages/*.deb "$rootdir/opt/"
chroot "$rootdir" bash -c "dpkg -i /opt/*.deb"
chroot "$rootdir" bash -c "rm /opt/*.deb"

# Clean apt cache
log "Cleaning apt cache"
chroot "$rootdir" apt clean

# Configure dynamic linker run-time bindings
log "Configuring dynamic linker run-time bindings"
chroot "$rootdir" ldconfig

# Enable userspace daemons
log "Generating fstab"
log "Enabling userspace daemons"
chroot "$rootdir" systemctl enable qrtr-ns pd-mapper tqftpserv rmtfs systemd-zram-setup@zram0.service

gen_fstab "$rootdir"

# Enable zram
log "Enabling zram"
cp ./drop/zram-generator.conf "$rootdir/etc/systemd/zram-generator.conf"

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
chroot "$rootdir" bash -c 'mkdir ~Debian-gdm/.config/'
chroot "$rootdir" bash -c 'chown Debian-gdm: ~Debian-gdm/.config/'
chroot "$rootdir" bash -c 'chmod 700 ~Debian-gdm/.config'
chroot "$rootdir" bash -c 'cp /etc/skel/.config/monitors.xml ~Debian-gdm/.config/'
chroot "$rootdir" bash -c 'chmod 644 ~Debian-gdm/.config/monitors.xml'
chroot "$rootdir" bash -c 'chown Debian-gdm: ~Debian-gdm/.config/monitors.xml'
# ---

# Finish image
log "Finishing image"
detach_chroot "$rootdir"
umount_image "$rootdir"
trim_image "$IMAGE_NAME"

log "Stop creating image: $IMAGE_NAME"

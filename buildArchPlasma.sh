#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
  sudo -E "$0" "$@"
  exit $?
fi

source common.sh

# Ensure that bsdtar is installed
which bsdtar > /dev/null 2>&1 || {
  echo "bsdtar not found"
  exit 1
}

IMAGE_NAME="ArchLinuxArmPlasma"

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

# Add custom mirrorlist
log "Adding mirrorlist"
cp ./drop/mirrorlist "$rootdir/etc/pacman.d/mirrorlist"

# Install minimal desktop environment
log "Populating pacman key store"
chroot "$rootdir" pacman-key --init
chroot "$rootdir" pacman-key --populate archlinuxarm
log "Enable pacman parallel downloads"
chroot "$rootdir" sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
log "Update key store"
chroot "$rootdir" pacman -Sy archlinux-keyring archlinuxarm-keyring --noconfirm
log "Updating system and installing needed packages"
chroot "$rootdir" pacman -Syu sudo plasma grub konsole dolphin ark bluez bluez-utils xorg-xrandr xorg-xinput qt5-virtualkeyboard vulkan-freedreno networkmanager zram-generator --noconfirm

# Install nabu specific packages
log "Installing nabu kernel, modules, firmwares and userspace daemons"
cp ./packages/*.zst "$rootdir/opt/"
chroot "$rootdir" bash -c "pacman -U /opt/*.zst --noconfirm"
rm "$rootdir"/opt/*.zst

# Enable userspace daemons
log "Enabling userspace daemons"
chroot "$rootdir" systemctl enable qrtr-ns pd-mapper tqftpserv rmtfs sddm bluetooth NetworkManager systemd-zram-setup@zram0.service

# Clean pacman cache
log "Cleaning pacman cache"
yes | chroot "$rootdir" pacman -Scc

log "Generating fstab"
gen_fstab "$rootdir"

# Add %wheel to sudoers
log "Adding %wheel to sudoers"
cp ./drop/00_image_builder "$rootdir/etc/sudoers.d/00_image_builder"

# Enable zram
log "Enabling zram"
cp ./drop/zram-generator.conf "$rootdir/etc/systemd/zram-generator.conf"

# Generate en_US locale
log "Generating en_US locale"
sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" "$rootdir/etc/locale.gen"
chroot "$rootdir" locale-gen
echo "LANG=en_US.UTF-8" > "$rootdir/etc/locale.conf"

# +++ Setup sddm
log "Configuring sddm"
echo '#!/bin/sh
# Xsetup - run as root before the login dialog appears
xrandr --output DSI-1 --rotate right
xinput set-prop "NVTCapacitiveTouchScreen" "Coordinate Transformation Matrix" 0 1 0 -1 0 1 0 0 1' > "$rootdir/usr/share/sddm/scripts/Xsetup"
chmod 755 "$rootdir/usr/share/sddm/scripts/Xsetup"
echo "[General]
DisplayServer=x11
InputMethod=qtvirtualkeyboard

[Theme]
Current=breeze

[X11]
DisplayCommand=/usr/share/sddm/scripts/Xsetup" > "$rootdir/usr/lib/sddm/sddm.conf.d/nabu.conf"
chmod 644 "$rootdir/usr/lib/sddm/sddm.conf.d/nabu.conf"
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

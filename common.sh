#!/usr/bin/env bash

SIMPLEINIT_CMDLINE="root=PARTLABEL=linux loglevel=3 fbcon=rotate:1"

function log() {
    printf "\e[1m\e[92m==>\e[0m \e[1m%s\e[0m\n" "$*"
}
function log_err() {
    printf "\e[1m\e[31m==>\e[0m \e[1m%s\e[0m\n" "$*"
}

function create_image() {
    name="$(realpath "./raw/${1}.img")"
    if [ -z "$2" ]; then
        size="10GB"
    else
        size="${2}GB"
    fi
    
    if [ -f "$name" ]; then
        rm "$name"
    fi

    truncate --size "$size" "$name"
    mkfs.ext4 "$name"
}

function trim_image() {
    name="$(realpath "./raw/${1}.img")"
    e2fsck -f "$name"
    resize2fs -M "$name"
}

function mount_image() {
    mountdir="$(mktemp --tmpdir=./tmp/ -d)"
    mountdir="$(realpath "$mountdir")"
    mount -o loop "./raw/${1}.img" "$mountdir"
    mkdir -p "$mountdir/boot/efi"
    mkdir -p "$mountdir/boot/simpleinit"
    mount -o size=512M,mode=0755 -t tmpfs nabu_esp "$mountdir/boot/efi"
    mount -o size=512M,mode=0755 -t tmpfs nabu_simpleinit "$mountdir/boot/simpleinit"
    sed "s|{cmdline}|$SIMPLEINIT_CMDLINE|g" < ./drop/simpleinit.uefi.cfg > "$mountdir/boot/simpleinit/simpleinit.uefi.cfg"
    printf "%s" "$mountdir"
}

function gen_fstab() {
    if [ -d "${1}/etc/" ]; then
        [ -f "${1}/etc/fstab" ] && rm "${1}/etc/fstab"
        cp ./drop/fstab "${1}/etc/fstab"
    fi
}

function umount_image() {
    if [ -d "${1}" ]; then
        rootdir="$(realpath "${1}")"
        mkdir "$rootdir/opt/nabu/" -p
        tar -cf "$rootdir/opt/nabu/efi.tar" -C "$rootdir/" boot/
        cp ./drop/postinstall "$rootdir/opt/nabu/postinstall"
        chmod +x "$rootdir/opt/nabu/postinstall"
        umount "$rootdir/boot/efi"
        umount "$rootdir/boot/simpleinit"
        umount "$rootdir"
        rm -d "$rootdir"
    fi
}

function prepare_chroot() {
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
    if [ -d "$1" ]; then
        rootdir="$(realpath "$1")"

        mount --bind /proc "$rootdir/proc"
        mount --bind /sys "$rootdir/sys"
        mount --bind /dev "$rootdir/dev"
        mount --bind /dev/pts "$rootdir/dev/pts"
    fi

    if uname -m | grep -q aarch64 || [ -f "/proc/sys/fs/binfmt_misc/qemu-aarch64" ]; then
        echo "Cancel qemu install for arm64"
    else
        wget -N https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static -O ./cache/qemu-aarch64-static
        install -m755 ./cache/qemu-aarch64-static "$rootdir/"

        # shellcheck disable=SC2028
        echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' > /proc/sys/fs/binfmt_misc/register
    
        # shellcheck disable=SC2028
        echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' > /proc/sys/fs/binfmt_misc/register
    
    fi
}

function detach_chroot() {
    if [ -d "$1" ]; then
        rootdir=$(realpath "$1")
        blocking=$(lsof -t "$rootdir")
        if [ -n "$blocking" ]; then
            kill -9 "$blocking"
        fi
        killall gpg-agent > /dev/null 2>&1
        umount "$rootdir/proc"
        umount "$rootdir/sys"
        umount "$rootdir/dev/pts"
        umount "$rootdir/dev"
    fi

    if uname -m | grep -q aarch64; then
        echo "Cancel qemu uninstall for arm64"
    else
        if [ -f "/proc/sys/fs/binfmt_misc/aarch64" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/aarch64
        fi
        if [ -f "/proc/sys/fs/binfmt_misc/aarch64ld" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/aarch64ld
        fi
        if [ -f "$rootdir/qemu-aarch64-static" ]; then
            rm "$rootdir/qemu-aarch64-static"
        fi
    fi
}

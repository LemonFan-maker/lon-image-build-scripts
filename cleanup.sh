#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
  sudo -E "$0" "$@"
  exit $?
fi

source common.sh

# shellcheck disable=SC2162
if find ./tmp/ -mindepth 1 -maxdepth 1 | read; then
  for d in ./tmp/*/; do
    log "Unmounting $d"
    detach_chroot "$d"
    umount "$d/boot/simpleinit" 2> /dev/null
    umount "$d/boot/efi" 2> /dev/null
    umount ./tmp/tmp.* 2> /dev/null
    rm -d "$d"
  done
else
  log_err "Nothing to clean"
fi
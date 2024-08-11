#!/usr/bin/env bash

# Restart as root
if [ "$(id -u)" != "0" ]; then
  sudo -E "$0" "$@"
  exit $?
fi

source common.sh

# Begin script

# shellcheck disable=SC2162
find ./tmp/ -mindepth 1 -maxdepth 1 | read || {
  log_err "Nothing to clean"
  exit 1
}

for d in ./tmp/*/; do
  log "Unmounting $d"
  detach_chroot "$d"
  umount "$d/boot/simpleinit" 2> /dev/null
  umount "$d/boot/efi" 2> /dev/null
  umount ./tmp/tmp.* 2> /dev/null
  rm -d "$d"
done
#!/usr/bin/env bash

source common.sh

# Ensure that lon-tool installed
which lon-tool > /dev/null 2>&1 || {
    log_err "lon-tool not found"
    exit 1
}

# shellcheck disable=SC2162
find ./raw/ -mindepth 1 -maxdepth 1 | read || {
    log_err "Nothing to compress"
    exit 1
}

# Settings
DATE=$(date +"%d-%m-%y")

# Begin script
log "Start compressing images"
log "Current date: ${DATE}"

for image in raw/*; do
    full_image_path=$(realpath "$image")
    image_name=$(basename "$full_image_path")
    lni_name="${image_name/.img/""}"
    full_lni_path=$(realpath "./out/${image_name/.img/".lni"}")
    log "Compressing $lni_name"
    lon-tool image create -n "$lni_name" -v "$DATE" "$full_image_path" "$full_lni_path"
done

log "Stop compressing images"
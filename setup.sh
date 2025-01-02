#!/bin/bash

shopt -s globstar

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SOURCE_DIR="$HOME"
TARGET_DIRS=$(ls "$SCRIPT_DIR"/*/ -d)

EXCLUDES=(-not -path "*powershell*" -not -path "*AppData*")

for TARGET_DIR in $TARGET_DIRS; do
    TARGET_FILES=$(find "$TARGET_DIR" -type f "${EXCLUDES[@]}")
    if [ -z "$TARGET_FILES" ]; then
        continue
    fi
    while IFS= read -r TARGET_FILE; do
        SOURCE_PATH="$SOURCE_DIR/$(echo "${TARGET_FILE/$SOURCE_DIR/}" | cut -d '/' -f4-)"
        mkdir -p "$(dirname "${SOURCE_PATH}")"
        ln -sf "$TARGET_FILE" "$SOURCE_PATH"
    done <<<"$TARGET_FILES"
done

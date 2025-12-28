#!/bin/bash

shopt -s globstar

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SOURCE_DIR="$HOME"
TARGET_DIRS=$(ls "$SCRIPT_DIR"/*/ -d)

EXCLUDES=(-not -path "*powershell*" -not -path "*AppData*" -not -path "*packages*")

install_packages() {
    local PACKAGE_DIR="$SCRIPT_DIR/packages"
    local PACKAGES PKG_MGR PKG_FILE INSTALL_CMD

    if command -v dnf &>/dev/null; then
        PKG_MGR="DNF"
        PKG_FILE="dnf.txt"
        INSTALL_CMD="sudo dnf install -y --skip-unavailable"
    elif command -v apt &>/dev/null; then
        PKG_MGR="APT"
        PKG_FILE="apt.txt"
        INSTALL_CMD="sudo apt update && sudo apt install -y"
    else
        return
    fi

    PACKAGES=$(cat "$PACKAGE_DIR/$PKG_FILE" 2>/dev/null | tr '\n' ' ')
    [ -z "$PACKAGES" ] && return

    PKG_COUNT=$(echo $PACKAGES | wc -w)
    echo "$PKG_MGR packages to install ($PKG_COUNT):"
    echo "  $PACKAGES"
    read -p "Install with $PKG_MGR? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && $INSTALL_CMD $PACKAGES
}

install_packages

echo "Creating symlinks for dotfiles..."
for TARGET_DIR in $TARGET_DIRS; do
    TARGET_FILES=$(find "$TARGET_DIR" -type f "${EXCLUDES[@]}")
    if [ -z "$TARGET_FILES" ]; then
        continue
    fi
    while IFS= read -r TARGET_FILE; do
        SOURCE_PATH="$SOURCE_DIR/$(echo "${TARGET_FILE/$SOURCE_DIR/}" | cut -d '/' -f4-)"
        mkdir -p "$(dirname "${SOURCE_PATH}")"
        ln -sf "$TARGET_FILE" "$SOURCE_PATH"
        echo "  Linked: $TARGET_FILE -> $SOURCE_PATH"
    done <<<"$TARGET_FILES"
done

echo ""
echo "Setup complete!"

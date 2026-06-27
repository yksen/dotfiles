#!/bin/bash

shopt -s globstar

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SOURCE_DIR="$HOME"
TARGET_DIRS=$(ls "$SCRIPT_DIR"/*/ -d)

EXCLUDES=(-not -path "*packages*")

# --- Colors (disabled when not a terminal) ---------------------------------
if [ -t 1 ]; then
    C_PROMPT='\033[1;36m' # bright cyan: questions to the user
    C_HEAD='\033[1;35m'   # magenta: section headings
    C_OK='\033[0;32m'     # green
    C_FAIL='\033[0;31m'   # red
    C_SKIP='\033[0;33m'   # yellow
    C_DIM='\033[2m'       # dimmed details
    C_RESET='\033[0m'
else
    C_PROMPT='' C_HEAD='' C_OK='' C_FAIL='' C_SKIP='' C_DIM='' C_RESET=''
fi

# --- Counters --------------------------------------------------------------
TOTAL_OK=0 TOTAL_FAIL=0 TOTAL_SKIP=0 # aggregated across all sections
SEC_OK=0 SEC_FAIL=0 SEC_SKIP=0       # reset per section

# Print a colored y/N question and read a single keypress into REPLY.
ask() {
    printf "${C_PROMPT}%s${C_RESET} " "$1"
    read -p "(y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

heading() {
    SEC_OK=0 SEC_FAIL=0 SEC_SKIP=0
    printf "${C_HEAD}==> %s${C_RESET}\n" "$1"
}

# log <ok|fail|skip> <message>  — one compact line per operation.
log() {
    local status="$1" msg="$2"
    case "$status" in
    ok) printf "  ${C_OK}[ OK ]${C_RESET} %s\n" "$msg"; ((SEC_OK++, TOTAL_OK++)) ;;
    fail) printf "  ${C_FAIL}[FAIL]${C_RESET} %s\n" "$msg"; ((SEC_FAIL++, TOTAL_FAIL++)) ;;
    skip) printf "  ${C_SKIP}[SKIP]${C_RESET} %s\n" "$msg"; ((SEC_SKIP++, TOTAL_SKIP++)) ;;
    esac
}

# Print the per-section tally line.
section_summary() {
    printf "    ${C_DIM}%d ok, %d failed, %d skipped${C_RESET}\n" \
        "$SEC_OK" "$SEC_FAIL" "$SEC_SKIP"
}

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
        heading "Packages"
        log skip "no supported package manager (dnf/apt) found"
        section_summary
        return
    fi

    PACKAGES=$(cat "$PACKAGE_DIR/$PKG_FILE" 2>/dev/null | tr '\n' ' ')
    if [ -z "$PACKAGES" ]; then
        heading "Packages"
        log skip "no packages listed in $PKG_FILE"
        section_summary
        return
    fi

    local PKG_COUNT
    PKG_COUNT=$(echo $PACKAGES | wc -w)
    printf "${C_DIM}%s packages (%d): %s${C_RESET}\n" "$PKG_MGR" "$PKG_COUNT" "$PACKAGES"

    heading "Packages"
    if ! ask "Install with $PKG_MGR?"; then
        log skip "package installation declined"
        section_summary
        return
    fi

    if $INSTALL_CMD $PACKAGES; then
        log ok "$PKG_MGR install finished ($PKG_COUNT requested)"
    else
        log fail "$PKG_MGR install exited non-zero"
    fi
    section_summary
}

create_symlinks() {
    heading "Symlinks"
    if ! ask "Create symlinks for dotfiles?"; then
        log skip "symlink creation declined"
        section_summary
        return
    fi

    for TARGET_DIR in $TARGET_DIRS; do
        TARGET_FILES=$(find "$TARGET_DIR" -type f "${EXCLUDES[@]}")
        if [ -z "$TARGET_FILES" ]; then
            continue
        fi
        while IFS= read -r TARGET_FILE; do
            SOURCE_PATH="$SOURCE_DIR/$(echo "${TARGET_FILE/$SOURCE_DIR/}" | cut -d '/' -f4-)"
            if mkdir -p "$(dirname "${SOURCE_PATH}")" && ln -sf "$TARGET_FILE" "$SOURCE_PATH"; then
                log ok "${SOURCE_PATH/#$HOME/\~}"
            else
                log fail "${SOURCE_PATH/#$HOME/\~}"
            fi
        done <<<"$TARGET_FILES"
    done
    section_summary
}

rebuild_font_cache() {
    heading "Font cache"
    if ! ask "Rebuild font cache?"; then
        log skip "font cache rebuild declined"
        section_summary
        return
    fi

    if fc-cache -f; then
        log ok "font cache rebuilt"
    else
        log fail "fc-cache exited non-zero"
    fi
    section_summary
}

final_summary() {
    printf "\n${C_HEAD}==> Summary${C_RESET}\n"
    printf "  ${C_OK}%d ok${C_RESET}, ${C_FAIL}%d failed${C_RESET}, ${C_SKIP}%d skipped${C_RESET}\n" \
        "$TOTAL_OK" "$TOTAL_FAIL" "$TOTAL_SKIP"
    [ "$TOTAL_FAIL" -gt 0 ] && return 1
    return 0
}

main() {
    install_packages
    create_symlinks
    rebuild_font_cache
    final_summary
}

main

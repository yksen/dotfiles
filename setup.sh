#!/bin/bash

shopt -s globstar

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SOURCE_DIR="$HOME"
TARGET_DIRS=$(ls "$SCRIPT_DIR"/*/ -d)

EXCLUDES=(-not -path "*packages*")

LOG_FILE="${TMPDIR:-/tmp}/dotfiles-setup.log"

# --- Colors (disabled when not a terminal) ---------------------------------
if [ -t 1 ]; then
    C_PROMPT='\033[1;36m' # bright cyan: questions to the user
    C_OK='\033[0;32m'     # green
    C_FAIL='\033[0;31m'   # red
    C_SKIP='\033[0;33m'   # yellow
    C_DIM='\033[2m'       # dimmed details
    C_RESET='\033[0m'
else
    C_PROMPT='' C_OK='' C_FAIL='' C_SKIP='' C_DIM='' C_RESET=''
fi

# Section outcomes, aggregated for the final summary.
STEPS_OK=0 STEPS_FAIL=0 STEPS_SKIP=0

# Print a colored y/N question and read a single keypress into REPLY.
ask() {
    printf "${C_PROMPT}%s${C_RESET} " "$1"
    read -p "(y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# status <ok|fail|skip> <message> [detail]
# One line per section: a colored status tag, a message, and an optional
# dimmed breakdown of the counts behind it.
status() {
    local kind="$1" msg="$2" detail="$3" tag
    case "$kind" in
    ok) tag="${C_OK}[ OK ]${C_RESET}"; ((STEPS_OK++)) ;;
    fail) tag="${C_FAIL}[FAIL]${C_RESET}"; ((STEPS_FAIL++)) ;;
    skip) tag="${C_SKIP}[SKIP]${C_RESET}"; ((STEPS_SKIP++)) ;;
    esac
    printf "  %b %s\n" "$tag" "$msg"
    [ -n "$detail" ] && printf "    ${C_DIM}%s${C_RESET}\n" "$detail"
}

# Run a command with all output redirected to the log file.
run_quiet() {
    echo "\$ $*" >>"$LOG_FILE"
    "$@" >>"$LOG_FILE" 2>&1
}

install_packages() {
    local PACKAGE_DIR="$SCRIPT_DIR/packages"
    local PACKAGES

    if ! command -v dnf &>/dev/null; then
        status skip "Packages: dnf not found"
        return
    fi

    PACKAGES=$(grep -vE '^\s*(#|$)' "$PACKAGE_DIR/dnf.txt" 2>/dev/null | tr '\n' ' ')
    if [ -z "$PACKAGES" ]; then
        status skip "Packages: nothing listed in dnf.txt"
        return
    fi

    local requested
    requested=$(echo $PACKAGES | wc -w)

    if ! ask "Install $requested packages with dnf?"; then
        status skip "Packages: declined" "$requested requested"
        return
    fi

    echo "\$ sudo dnf install -y --skip-unavailable $PACKAGES" >>"$LOG_FILE"
    local out rc
    out=$(LC_ALL=C sudo dnf install -y --skip-unavailable $PACKAGES 2>&1)
    rc=$?
    echo "$out" >>"$LOG_FILE"

    # Tally outcomes from dnf's output; "new" is whatever is left over.
    local already missing installed
    already=$(grep -c 'is already installed' <<<"$out")
    missing=$(grep -c 'No match for argument' <<<"$out")
    installed=$((requested - already - missing))
    [ "$installed" -lt 0 ] && installed=0

    local detail="$installed installed, $already already present, $missing not found"
    if [ "$rc" -eq 0 ]; then
        status ok "Packages" "$detail"
    else
        status fail "Packages (dnf exited $rc, see $LOG_FILE)" "$detail"
    fi
}

create_symlinks() {
    if ! ask "Create symlinks for dotfiles?"; then
        status skip "Symlinks: declined"
        return
    fi

    local created=0 existed=0 failed=0
    for TARGET_DIR in $TARGET_DIRS; do
        TARGET_FILES=$(find "$TARGET_DIR" -type f "${EXCLUDES[@]}")
        [ -z "$TARGET_FILES" ] && continue
        while IFS= read -r TARGET_FILE; do
            local SOURCE_PATH
            SOURCE_PATH="$SOURCE_DIR/$(echo "${TARGET_FILE/$SOURCE_DIR/}" | cut -d '/' -f4-)"
            # Already linked to the right target -> nothing to do.
            if [ "$(readlink -f "$SOURCE_PATH" 2>/dev/null)" = "$TARGET_FILE" ]; then
                ((existed++))
                continue
            fi
            if mkdir -p "$(dirname "$SOURCE_PATH")" 2>>"$LOG_FILE" &&
                ln -sf "$TARGET_FILE" "$SOURCE_PATH" 2>>"$LOG_FILE"; then
                ((created++))
            else
                ((failed++))
                echo "failed to link $SOURCE_PATH -> $TARGET_FILE" >>"$LOG_FILE"
            fi
        done <<<"$TARGET_FILES"
    done

    local detail="$created created, $existed already linked, $failed failed"
    if [ "$failed" -eq 0 ]; then
        status ok "Symlinks" "$detail"
    else
        status fail "Symlinks (see $LOG_FILE)" "$detail"
    fi
}

rebuild_font_cache() {
    if ! ask "Rebuild font cache?"; then
        status skip "Font cache: declined"
        return
    fi

    # fc-cache -fv prints one "caching, N fonts" line per scanned dir.
    echo "\$ fc-cache -fv" >>"$LOG_FILE"
    local out rc fonts dirs
    out=$(fc-cache -fv 2>&1)
    rc=$?
    echo "$out" >>"$LOG_FILE"

    fonts=$(grep -oE '[0-9]+ fonts' <<<"$out" | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null)
    dirs=$(grep -c 'caching' <<<"$out")
    [ -z "$fonts" ] && fonts=0

    local detail="$fonts fonts across $dirs directories"
    if [ "$rc" -eq 0 ]; then
        status ok "Font cache" "$detail"
    else
        status fail "Font cache (fc-cache exited $rc, see $LOG_FILE)" "$detail"
    fi
}

final_summary() {
    printf "\n  ${C_OK}%d ok${C_RESET}, ${C_FAIL}%d failed${C_RESET}, ${C_SKIP}%d skipped${C_RESET}\n" \
        "$STEPS_OK" "$STEPS_FAIL" "$STEPS_SKIP"
    [ "$STEPS_FAIL" -gt 0 ] && printf "  ${C_DIM}details: %s${C_RESET}\n" "$LOG_FILE"
    [ "$STEPS_FAIL" -gt 0 ] && return 1
    return 0
}

main() {
    : >"$LOG_FILE"
    install_packages
    create_symlinks
    rebuild_font_cache
    final_summary
}

main

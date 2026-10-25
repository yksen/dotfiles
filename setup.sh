#!/bin/bash

shopt -s globstar

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SOURCE_DIR="$HOME"
TARGET_DIRS=$(ls "$SCRIPT_DIR"/*/ -d)

EXCLUDES=(-not -path "*packages*" -not -path "*xorg.conf.d*" -not -path "*dconf*" -not -path "*systemd/system*")

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

# Append a line to the log (successful actions, so the log shows what was done).
log() {
    echo "$*" >>"$LOG_FILE"
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
        log "dnf: $detail"
        status ok "Packages" "$detail"
    else
        status fail "Packages (dnf exited $rc, see $LOG_FILE)" "$detail"
    fi
}

install_pipx_apps() {
    local PIPX_FILE="$SCRIPT_DIR/packages/pipx.txt"
    local APPS

    if ! command -v pipx &>/dev/null; then
        status skip "Pipx apps: pipx not found"
        return
    fi

    APPS=$(grep -vE '^\s*(#|$)' "$PIPX_FILE" 2>/dev/null)
    if [ -z "$APPS" ]; then
        status skip "Pipx apps: nothing listed in pipx.txt"
        return
    fi

    local requested
    requested=$(echo "$APPS" | wc -l)

    if ! ask "Install $requested pipx app(s)?"; then
        status skip "Pipx apps: declined" "$requested requested"
        return
    fi

    # Package names already installed by pipx (first column of the short list).
    local present
    present=$(pipx list --short 2>/dev/null | awk '{print $1}')

    local installed=0 already=0 failed=0 app
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        if grep -qxF "$app" <<<"$present"; then
            ((already++))
            continue
        fi
        if run_quiet pipx install "$app"; then
            ((installed++))
            log "pipx installed $app"
        else
            ((failed++))
            echo "failed to pipx install $app" >>"$LOG_FILE"
        fi
    done <<<"$APPS"

    local detail="$installed installed, $already already present, $failed failed"
    if [ "$failed" -eq 0 ]; then
        status ok "Pipx apps" "$detail"
    else
        status fail "Pipx apps (see $LOG_FILE)" "$detail"
    fi
}

# Install/update binaries from GitHub releases (packages/github.txt) into
# ~/.local/bin. The installed tag is recorded in a stamp file, so reruns only
# touch repos whose latest release changed.
install_github_binaries() {
    local LIST="$SCRIPT_DIR/packages/github.txt"
    local BIN_DIR="$HOME/.local/bin"
    local STAMP_DIR="$HOME/.local/share/dotfiles-bins"
    local REPOS

    REPOS=$(grep -vE '^\s*(#|$)' "$LIST" 2>/dev/null)
    if [ -z "$REPOS" ]; then
        status skip "GitHub binaries: nothing listed in github.txt"
        return
    fi
    if ! command -v curl &>/dev/null; then
        status skip "GitHub binaries: curl not found"
        return
    fi

    # Resolve latest tag + asset URL for each repo; keep only those out of date.
    local todo=() uptodate=0 failed=0 repo name json tag url
    for repo in $REPOS; do
        name="${repo##*/}"
        echo "\$ curl https://api.github.com/repos/$repo/releases/latest" >>"$LOG_FILE"
        json=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>>"$LOG_FILE")
        tag=$(grep -m1 '"tag_name"' <<<"$json" | cut -d'"' -f4)
        url=$(grep -o '"browser_download_url": *"[^"]*"' <<<"$json" | cut -d'"' -f4 |
            grep -iE 'linux' | grep -iE 'x86_64|amd64' | grep -iE '\.tar\.gz$' | head -n1)
        if [ -z "$tag" ] || [ -z "$url" ]; then
            ((failed++))
            echo "no linux x86_64 tar.gz release found for $repo" >>"$LOG_FILE"
            continue
        fi
        if [ -x "$BIN_DIR/$name" ] && [ "$(cat "$STAMP_DIR/$name" 2>/dev/null)" = "$tag" ]; then
            ((uptodate++))
            log "github: $name $tag already up to date"
            continue
        fi
        todo+=("$repo|$tag|$url")
    done

    if [ "${#todo[@]}" -gt 0 ]; then
        if ! ask "Install/update ${#todo[@]} GitHub binary(ies) into ~/.local/bin?"; then
            status skip "GitHub binaries: declined" "${#todo[@]} pending, $uptodate up to date"
            return
        fi
    fi

    local installed=0 entry tmp
    mkdir -p "$BIN_DIR" "$STAMP_DIR"
    for entry in "${todo[@]}"; do
        IFS='|' read -r repo tag url <<<"$entry"
        name="${repo##*/}"
        tmp=$(mktemp -d)
        if run_quiet curl -fsSL -o "$tmp/asset.tar.gz" "$url" &&
            run_quiet tar -xzf "$tmp/asset.tar.gz" -C "$tmp" "$name" &&
            run_quiet install -m 755 "$tmp/$name" "$BIN_DIR/$name"; then
            echo "$tag" >"$STAMP_DIR/$name"
            ((installed++))
            log "github: installed $name $tag -> $BIN_DIR/$name"
        else
            ((failed++))
            echo "failed to install $repo $tag" >>"$LOG_FILE"
        fi
        rm -rf "$tmp"
    done

    local detail="$installed installed/updated, $uptodate up to date, $failed failed"
    if [ "$failed" -eq 0 ]; then
        status ok "GitHub binaries" "$detail"
    else
        status fail "GitHub binaries (see $LOG_FILE)" "$detail"
    fi
}

# Symlink ~/.local/bin/<name> to each app's exported (system) launcher.
# Args are "id=name" pairs.
link_flatpak_apps() {
    local BIN_DIR="$HOME/.local/bin" EXPORTS=/var/lib/flatpak/exports/bin pair app
    mkdir -p "$BIN_DIR"
    for pair in "$@"; do
        app="${pair%%=*}"
        [ -e "$EXPORTS/$app" ] || continue
        ln -sfn "$EXPORTS/$app" "$BIN_DIR/${pair#*=}"
        log "flatpak: linked $BIN_DIR/${pair#*=} -> $EXPORTS/$app"
    done
}

# Install Flatpak apps from Flathub (packages/flatpak.txt). The flathub remote
# is added only when missing; the flatpak package comes from dnf.txt. Each app
# also gets a short lowercase launcher symlink in ~/.local/bin.
install_flatpak_apps() {
    local LIST="$SCRIPT_DIR/packages/flatpak.txt"
    local APPS

    # Each line is "app-id command-name"; both columns are required.
    local id name links=() malformed=0
    while read -r id name; do
        [ -z "$id" ] && continue
        if [ -z "$name" ]; then
            ((malformed++))
            echo "flatpak.txt: no command name for $id, skipped" >>"$LOG_FILE"
            continue
        fi
        APPS+="$id "
        links+=("$id=$name")
    done < <(grep -vE '^\s*(#|$)' "$LIST" 2>/dev/null)
    if [ -z "$APPS" ]; then
        status skip "Flatpak: nothing listed in flatpak.txt"
        return
    fi

    # flatpak itself comes from dnf.txt, which is installed first.
    if ! command -v flatpak &>/dev/null; then
        status skip "Flatpak: flatpak not installed (add it to dnf.txt)"
        return
    fi

    local need_remote=0 todo=() app
    flatpak remotes --columns=name 2>/dev/null | grep -qx flathub || need_remote=1
    for app in $APPS; do
        flatpak info "$app" &>/dev/null || todo+=("$app")
    done

    local present=$(($(wc -w <<<"$APPS") - ${#todo[@]}))
    if [ "$need_remote" -eq 0 ] && [ "${#todo[@]}" -eq 0 ]; then
        log "flatpak: all apps already installed"
        link_flatpak_apps "${links[@]}"
        status ok "Flatpak apps" "0 installed, $present already present"
        return
    fi

    if ! ask "Install ${#todo[@]} Flatpak app(s) from Flathub?"; then
        status skip "Flatpak: declined" "${#todo[@]} pending, $present already present"
        return
    fi

    if [ "$need_remote" -eq 1 ] && ! run_quiet sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo; then
        status fail "Flatpak (could not add flathub remote, see $LOG_FILE)"
        return
    fi

    local installed=0 failed=0
    for app in "${todo[@]}"; do
        if run_quiet sudo flatpak install -y --noninteractive flathub "$app"; then
            ((installed++))
            log "flatpak: installed $app"
        else
            ((failed++))
        fi
    done

    link_flatpak_apps "${links[@]}"

    local detail="$installed installed, $present already present, $failed failed"
    failed=$((failed + malformed))
    [ "$malformed" -gt 0 ] && detail+=", $malformed without a command name"
    if [ "$failed" -eq 0 ]; then
        status ok "Flatpak apps" "$detail"
    else
        status fail "Flatpak apps (see $LOG_FILE)" "$detail"
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
                log "already linked $SOURCE_PATH"
                continue
            fi
            if mkdir -p "$(dirname "$SOURCE_PATH")" 2>>"$LOG_FILE" &&
                ln -sf "$TARGET_FILE" "$SOURCE_PATH" 2>>"$LOG_FILE"; then
                ((created++))
                log "linked $SOURCE_PATH -> $TARGET_FILE"
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
        log "fc-cache: $detail"
        status ok "Font cache" "$detail"
    else
        status fail "Font cache (fc-cache exited $rc, see $LOG_FILE)" "$detail"
    fi
}

apply_gsettings() {
    local KEYFILE="$SCRIPT_DIR/dconf/dconf.ini"

    if ! command -v dconf &>/dev/null; then
        status skip "GSettings: dconf not found"
        return
    fi
    if [ ! -f "$KEYFILE" ]; then
        status skip "GSettings: no keyfile at dconf/dconf.ini"
        return
    fi

    if ! ask "Load GSettings from dconf/dconf.ini?"; then
        status skip "GSettings: declined"
        return
    fi

    local keys
    keys=$(grep -cE '^\S+=' "$KEYFILE")
    echo "\$ dconf load / < $KEYFILE" >>"$LOG_FILE"
    if dconf load / <"$KEYFILE" 2>>"$LOG_FILE"; then
        log "dconf: loaded $keys key(s) from $KEYFILE"
        status ok "GSettings" "$keys key(s) loaded from dconf.ini"
    else
        status fail "GSettings (dconf load failed, see $LOG_FILE)"
    fi
}

ROOT_FILES=(
    "x11/xorg.conf.d/60-mouse-accel.conf:/etc/X11/xorg.conf.d/60-mouse-accel.conf"
    "systemd/system/lightdm.service.d/evdi-before-x.conf:/etc/systemd/system/lightdm.service.d/evdi-before-x.conf"
)

install_root_files() {
    if [ "${#ROOT_FILES[@]}" -eq 0 ]; then
        status skip "Root files: nothing to install"
        return
    fi

    # Skip the prompt (and sudo) entirely when every file is already in place.
    local needs_install=0 entry src dest
    for entry in "${ROOT_FILES[@]}"; do
        src="$SCRIPT_DIR/${entry%%:*}" dest="${entry#*:}"
        cmp -s "$src" "$dest" || needs_install=1
    done

    if [ "$needs_install" -eq 0 ]; then
        log "root files: already up to date"
        status ok "Root files" "already up to date"
        return
    fi

    if ! ask "Copy ${#ROOT_FILES[@]} file(s) to system paths (needs sudo)?"; then
        status skip "Root files: declined"
        return
    fi

    local copied=0 failed=0
    for entry in "${ROOT_FILES[@]}"; do
        src="$SCRIPT_DIR/${entry%%:*}" dest="${entry#*:}"
        if run_quiet sudo mkdir -p "$(dirname "$dest")" && run_quiet sudo cp "$src" "$dest"; then
            ((copied++))
            log "copied $src -> $dest"
        else
            ((failed++))
            echo "failed to copy $src -> $dest" >>"$LOG_FILE"
        fi
    done

    local detail="$copied copied, $failed failed"
    if [ "$failed" -eq 0 ]; then
        status ok "Root files" "$detail"
    else
        status fail "Root files (see $LOG_FILE)" "$detail"
    fi
}

# systemd user units are symlinked by create_symlinks but not activated by it;
# enable (and start) the ones that need to be running for the session.
enable_user_units() {
    local UNITS=(i3-session-save.service)

    if ! command -v systemctl &>/dev/null; then
        status skip "User units: systemctl not found"
        return
    fi

    if ! ask "Enable ${#UNITS[@]} systemd user unit(s)?"; then
        status skip "User units: declined"
        return
    fi

    run_quiet systemctl --user daemon-reload

    local enabled=0 failed=0 unit
    for unit in "${UNITS[@]}"; do
        if run_quiet systemctl --user enable --now "$unit"; then
            ((enabled++))
            log "enabled and started $unit"
        else
            ((failed++))
            echo "failed to enable $unit" >>"$LOG_FILE"
        fi
    done

    local detail="$enabled enabled, $failed failed"
    if [ "$failed" -eq 0 ]; then
        status ok "User units" "$detail"
    else
        status fail "User units (see $LOG_FILE)" "$detail"
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
    install_pipx_apps
    install_github_binaries
    install_flatpak_apps
    create_symlinks
    rebuild_font_cache
    apply_gsettings
    install_root_files
    enable_user_units
    final_summary
}

main

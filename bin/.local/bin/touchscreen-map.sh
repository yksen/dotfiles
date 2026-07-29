#!/usr/bin/env bash
# Map the built-in touchscreen onto one output, on demand.
#
# The digitizer's Coordinate Transformation Matrix defaults to identity, which
# spans the entire X screen (3000x3120 with both DisplayLink monitors attached),
# so a tap on the laptop panel puts the cursor on an external monitor instead.
# The matrix is fractions of the whole screen, so it also stops being correct
# whenever the layout changes - hence a keybind to retarget or re-apply rather
# than a one-shot setting. Deliberately no daemon: the touchscreen is used
# rarely enough that a background process is not worth it.
#
# Note on rotated outputs: xinput reads the CRTC rotation (XRRGetCrtcInfo) and
# composes it into the matrix, assuming the digitizer turns with the output. On
# DVI-I-1-1 (rotate left) that yields [0 -0.36 0.36; 0.615 0 0], so a rightward
# swipe on the panel drives the cursor *down* the portrait monitor. Aspect is
# nearly preserved (panel 1920x1200 -> 1920x1080 of screen), but the axes are
# turned. Fine for the panel itself, which is never rotated; just be aware of it
# when cycling onto a rotated monitor.
#
# Invoked from ~/.config/i3/config:
#   exec --no-startup-id ~/.local/bin/touchscreen-map.sh --startup
#   bindsym Control+$mod+t exec --no-startup-id ~/.local/bin/touchscreen-map.sh --cycle
#
# Usage: touchscreen-map.sh [--startup | --cycle | --reset | <output>]
#   (no args)   map to the laptop panel
#   --startup   wait for the layout to settle, then map to the laptop panel
#   --cycle     advance to the next active output, wrapping - also the way to
#               re-apply the mapping after a dock/undock changed the screen size
#   --reset     identity: let touch span the whole X screen again
#   <output>    map to that RandR output by name

set -euo pipefail

PANEL=eDP
STATE="${XDG_RUNTIME_DIR:-/tmp}/touchscreen-map.target"
SETTLE_TRIES=15

note() { notify-send -t 2500 "Touchscreen" "$1" 2>/dev/null || true; }

die() {
    printf 'touchscreen-map: %s\n' "$1" >&2
    note "$1"
    exit 1
}

# Name of the first non-master device reporting a direct-touch class.
#
# Excluding masters is essential, not cosmetic: "Virtual core pointer" inherits
# XITouchClass from this very device, so it also reports "Touch mode: direct" and
# owns a Coordinate Transformation Matrix - mapping it would confine the mouse,
# touchpad and TrackPoint to one output too. Testing !~ /\[master/ rather than
# ~ /\[slave  pointer/ also keeps floating slaves visible (and the real listing
# has two spaces there, so an exact-space regex is brittle).
#
# Returns the NAME, not the id: X recycles device ids, and the name is unique to
# the slave, so it can never resolve to the master.
find_touchscreen() {
    local id
    id=$(xinput list --long 2>/dev/null | awk '
        /\[(master|slave|floating slave)/ {
            keep = ($0 !~ /\[master/)
            id = (match($0, /id=[0-9]+/)) ? substr($0, RSTART + 3, RLENGTH - 3) : ""
            next
        }
        keep && id != "" && /Touch mode: direct/ { print id; exit }
    ')
    [ -n "$id" ] || return 1
    xinput list "$id" 2>/dev/null |
        awk -F'\t' 'NR == 1 { sub(/[[:space:]]+$/, "", $1); print $1 }'
}

# Active RandR outputs, in xrandr's order. Read from xrandr rather than i3 so we
# never see i3's synthetic inactive "xroot-0", which is not a RandR output.
outputs() { xrandr --listmonitors | awk 'NR > 1 { print $NF }'; }

# map_to <output> [quiet]
map_to() {
    local target=$1 quiet=${2-}
    # xinput reports "Unable to find output ..." on stdout, not stderr, so both
    # streams have to go: die() already says the same thing more briefly.
    xinput map-to-output "$DEVICE" "$target" >/dev/null 2>&1 ||
        die "could not map touch to $target"
    printf '%s\n' "$target" >"$STATE"
    [ -n "$quiet" ] || note "touch → $target"
}

DEVICE=$(find_touchscreen) || die "no touchscreen found"

case "${1-}" in
    --reset)
        xinput map-to-output "$DEVICE" all >/dev/null 2>&1 ||
            die "could not reset touch mapping"
        rm -f "$STATE"
        note "touch → whole screen"
        ;;
    --cycle)
        mapfile -t outs < <(outputs)
        [ "${#outs[@]}" -gt 0 ] || die "no active outputs"
        current=$(cat "$STATE" 2>/dev/null || true)
        # Falls back to outs[0] when the state file is missing or holds a name
        # that no longer exists - DisplayLink output names change across replug.
        # outs[0] is the panel, which is the safe default.
        next=${outs[0]}
        for i in "${!outs[@]}"; do
            if [ "${outs[i]}" = "$current" ]; then
                next=${outs[$(((i + 1) % ${#outs[@]}))]}
                break
            fi
        done
        map_to "$next"
        ;;
    --startup)
        # displaylink-setup.sh (i3 config:35) sleeps 2s and then commits several
        # RandR changes; mapping before it settles would bake in a stale screen
        # size. Wait for two identical layout reads, then map and exit - this is
        # a one-shot, not a background process.
        prev=""
        tries=0
        while [ "$tries" -lt "$SETTLE_TRIES" ]; do
            now=$(xrandr --listmonitors)
            if [ -n "$prev" ] && [ "$now" = "$prev" ]; then
                break
            fi
            prev=$now
            tries=$((tries + 1))
            sleep 1
        done
        # Docked with the lid shut, the panel is simply absent; nothing to do.
        has_panel=0
        while IFS= read -r o; do
            [ "$o" = "$PANEL" ] && has_panel=1
        done <<<"$(outputs)"
        if [ "$has_panel" -eq 1 ]; then
            map_to "$PANEL" quiet
        fi
        ;;
    "")
        map_to "$PANEL"
        ;;
    *)
        map_to "$1"
        ;;
esac

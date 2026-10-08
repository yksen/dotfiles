#!/usr/bin/env bash
# Set up and position a vkms virtual output, interactively via fzf.
#
# vkms must be loaded before X starts - hotplugging it into a running X session
# only half-registers it (no RandR provider). So it is NOT loaded permanently:
# it would add a GPU to every boot, including docked ones. Instead this script
# toggles /etc/modules-load.d/vkms.conf on demand (sudo); relogin to apply.
#
#   no Virtual- output yet -> offer to enable vkms at boot
#   Virtual- output exists -> position/resolve it, or disable vkms at boot
#
# Nothing here is a fixed per-machine name: the vkms output's own name varies
# ("Virtual-1" on a clean boot, "Virtual-1-N" after repeated hotplugs), hence
# the pattern match. Anchor output, side and resolution are asked every run.
#
# Capture through vkms is CPU-bound in Sunshine (no DMA-BUF zero-copy path),
# capping streaming around ~5fps - fine for extending the desktop, not for
# smooth streaming. See memory sunshine-tv-virtual-display.

set -euo pipefail

CONF=/etc/modules-load.d/vkms.conf

die() {
    printf 'virtual-display: %s\n' "$1" >&2
    exit 1
}

OUTPUT=$(xrandr --query | awk '$1 ~ /^Virtual-/ && $2 == "connected" { print $1; exit }')

if [ -z "$OUTPUT" ]; then
    action=$(printf '%s\n' "enable vkms at boot (needs sudo, then relogin)" cancel |
        fzf --prompt="No virtual output. ") || exit 0
    [[ $action == enable* ]] || exit 0
    echo vkms | sudo tee "$CONF" >/dev/null
    echo "vkms enabled. Relogin, then run this again."
    exit 0
fi

action=$(printf '%s\n' "position $OUTPUT" "disable vkms at boot (needs sudo)" cancel |
    fzf --prompt="Virtual output present. ") || exit 0
case $action in
disable*)
    sudo rm -f "$CONF"
    echo "vkms disabled at boot. Takes effect after reboot."
    exit 0
    ;;
position*) ;;
*) exit 0 ;;
esac

reference=$(xrandr --query | awk -v skip="$OUTPUT" '$2 == "connected" && $1 != skip { print $1 }' |
    fzf --prompt="Anchor $OUTPUT to which output? ") || die "no reference output chosen"

position=$(printf '%s\n' above below left-of right-of same-as |
    fzf --prompt="Position of $OUTPUT relative to $reference? ") || die "no position chosen"

mode=$(xrandr --query | awk -v o="$OUTPUT" '
    $1 == o { grab=1; next }
    grab && /^[^ ]/ { exit }
    grab { print $1 }
' | fzf --prompt="Resolution for $OUTPUT? ") || die "no resolution chosen"

xrandr --output "$OUTPUT" --mode "$mode" "--$position" "$reference"

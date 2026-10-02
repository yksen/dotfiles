#!/usr/bin/env bash
# Interactively position a vkms virtual output, every time this runs.
#
# vkms (loaded at boot by /etc/modules-load.d/vkms.conf) must be present before
# X starts - hotplugging it into a running X session only half-registers it (no
# RandR provider, confirmed via Xorg.0.log never progressing past "found device
# N" on a live modprobe). Loaded at boot, X gives it a real provider and output
# automatically, same as any other GPU.
#
# Nothing here is a fixed per-machine name: the vkms output's own name varies
# ("Virtual-1" on a clean boot, "Virtual-1-N" after repeated hotplugs within one
# X session), hence the pattern match. Which output to anchor to, which side,
# and which resolution are all asked interactively via fzf on every run -
# nothing is cached, so every run re-asks.
#
# Capture through vkms is CPU-bound in Sunshine (no DMA-BUF zero-copy path),
# capping streaming around ~5fps regardless of this setup - fine for extending
# the desktop, not for smooth streaming. A physical HDMI/DP dummy plug on a real
# GPU output is the fix if that ever matters; see memory sunshine-tv-virtual-display.
#
# Invoked from ~/.config/i3/config:
#   exec --no-startup-id ~/.local/bin/virtual-display.sh

set -euo pipefail

die() {
    printf 'virtual-display: %s\n' "$1" >&2
    exit 1
}

OUTPUT=$(xrandr --query | awk '$1 ~ /^Virtual-/ && $2 == "connected" { print $1; exit }')
[ -n "$OUTPUT" ] || exit 0

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

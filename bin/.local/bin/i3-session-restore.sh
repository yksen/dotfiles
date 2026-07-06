#!/usr/bin/env bash
# Restore the i3 session saved by i3-session-save.sh: relaunch programs and
# swallow them back into each workspace's saved layout, then best-effort move
# each workspace onto the output it was on. Meant to be run once on a fresh
# login (Ctrl+$mod+r) - running it with windows already open duplicates them.

set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

DIR="${XDG_STATE_HOME:-$HOME/.local/state}/i3-resurrect"
map="$DIR/ws-outputs.tsv"

if [ ! -f "$map" ]; then
    notify-send -t 3000 "i3 restore" "no saved session found" 2>/dev/null || true
    exit 0
fi

# Restore each saved workspace. Names come from the manifest (see save script:
# on-disk filenames aren't reversible). i3-resurrect re-derives the filename
# from the name, so restoring by the original name finds the right file.
count=0
while IFS=$'\t' read -r name output; do
    [ -z "$name" ] && continue
    i3-resurrect restore -w "$name" -d "$DIR" || true
    count=$((count + 1))
done <"$map"

# Best-effort: put each workspace back on its saved output if that output is
# currently connected. Return focus to wherever it ended up afterwards.
active=$(i3-msg -t get_outputs | jq -r '.[] | select(.active) | .name')
focused=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
while IFS=$'\t' read -r name output; do
    [ -z "$name" ] && continue
    grep -qxF "$output" <<<"$active" || continue
    i3-msg "workspace \"$name\"" >/dev/null
    i3-msg "move workspace to output \"$output\"" >/dev/null
done <"$map"
[ -n "$focused" ] && i3-msg "workspace \"$focused\"" >/dev/null

notify-send -t 3000 "i3 session restored" "$count workspaces" 2>/dev/null || true

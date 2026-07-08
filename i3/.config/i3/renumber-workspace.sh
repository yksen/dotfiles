#!/usr/bin/env bash
# Prompt for a new number and apply it to the focused workspace, keeping its
# label. The name format is "<num>:<label>"; we swap the leading number so
# `workspace number N` keybinds match the new number while the label is kept.
# Empty or non-numeric input leaves the workspace unchanged, and a number
# already used by another workspace is rejected to avoid merging them.

set -euo pipefail

ws=$(i3-msg -t get_workspaces)
name=$(jq -r '.[] | select(.focused).name' <<<"$ws")
cur=$(jq -r '.[] | select(.focused).num' <<<"$ws")

# Split off the current label (everything after the first ":", if any).
label=${name#*:}
[ "$label" = "$name" ] && label=""

new=$(dmenu -p "Renumber ws $name to:" < /dev/null)

case "$new" in
    ''|*[!0-9]*) exit 0 ;;
esac
new=$((10#$new))

# Nothing to do if the number is unchanged.
[ "$new" = "$cur" ] && exit 0

# Reject numbers already taken by another workspace.
if jq -e --argjson n "$new" 'any(.[]; (.focused | not) and .num == $n)' <<<"$ws" >/dev/null; then
    notify-send -u critical "i3" "Workspace number $new is already taken"
    exit 0
fi

if [ -z "$label" ]; then
    i3-msg "rename workspace to \"$new\""
else
    i3-msg "rename workspace to \"$new:$label\""
fi

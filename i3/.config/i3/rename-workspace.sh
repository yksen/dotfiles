#!/usr/bin/env bash
# Prompt for a label and apply it to the focused workspace as "<num>:<label>".
# The leading number is kept so `workspace number N` keybinds still match it,
# and i3bar shows the label right after the number. Empty input clears the
# label back to the bare number.

set -euo pipefail

num=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused).num')

label=$(dmenu -p "Rename ws $num:" < /dev/null)

if [ -z "$label" ]; then
    i3-msg "rename workspace to \"$num\""
else
    i3-msg "rename workspace to \"$num:$label\""
fi

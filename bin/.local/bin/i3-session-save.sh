#!/usr/bin/env bash
# Save the current i3 session (every workspace: layout + running programs) plus
# a workspace->output manifest, so it can be brought back after a reboot with
# i3-session-restore.sh. Invoked on i3 exit ($mod+Shift+e), on demand
# (Ctrl+$mod+s), and at session teardown (i3-session-save.service).

set -euo pipefail

# pipx-installed i3-resurrect lives in ~/.local/bin, which may be off PATH
# under systemd.
export PATH="$HOME/.local/bin:$PATH"

DIR="${XDG_STATE_HOME:-$HOME/.local/state}/i3-resurrect"
mkdir -p "$DIR"

# Don't clobber a good snapshot with an empty one: if i3 is already gone or no
# windows are open (e.g. this ran late during logout teardown), keep what we
# already have on disk.
windows=$(i3-msg -t get_tree 2>/dev/null \
    | jq '[recurse(.nodes[], .floating_nodes[]) | select(.window != null)] | length' 2>/dev/null \
    || echo 0)
if [ "${windows:-0}" -eq 0 ]; then
    notify-send -t 2500 "i3 session" "nothing to save (no open windows)" 2>/dev/null || true
    exit 0
fi

# i3-resurrect 1.4.5 has no "all workspaces" flag, so save each one. A failure
# on a single workspace shouldn't abort the rest.
while IFS= read -r ws; do
    i3-resurrect save -w "$ws" -d "$DIR" || true
done < <(i3-msg -t get_workspaces | jq -r '.[].name')

# Sidecar manifest: workspace name -> output. Doubles as the list of names for
# restore, because the on-disk filenames have separators stripped (e.g. the
# ':' in "2:label"), so they are not reversible to the real workspace name.
i3-msg -t get_workspaces | jq -r '.[] | "\(.name)\t\(.output)"' >"$DIR/ws-outputs.tsv"

wscount=$(i3-msg -t get_workspaces | jq 'length')
notify-send -t 2500 "i3 session saved" "$wscount workspaces, $windows windows" 2>/dev/null || true

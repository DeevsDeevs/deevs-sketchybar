#!/usr/bin/env bash

# Attaches a local herdr tab to a remote host's session and focuses one agent there.
#   $1  ssh alias
#   $2  pane id on that host (optional)
#
# Focusing a remote pane changes nothing you can see locally, so a click on a remote
# agent has to bring the session here. The tab is reused when one already points at
# this host, otherwise clicking twice leaves two tabs attached to the same place.

set -u
export PATH="/usr/bin:/bin:$PATH"

host="${1:-}"
pane="${2:-}"
tab="${3:-}"
[ -n "$host" ] || exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
label="@$host"

# The remote rc is where a version manager puts herdr on PATH; a plain ssh never reads it.
if [ -n "$pane" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=4 \
        -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
        -- "$host" "\$SHELL -ic 'herdr agent focus $pane'" >/dev/null 2>&1
fi

existing="$(herdr tab list 2>/dev/null |
    jq -r --arg l "$label" '.result.tabs[]? | select(.label == $l) | .tab_id' 2>/dev/null | head -1)"

if [ -n "$existing" ]; then
    herdr tab focus "$existing" >/dev/null 2>&1
else
    herdr tab create --label "$label" --focus \
        --env SHELL="$dir/herdr_remote_shell.sh" \
        --env HERDR_REMOTE_HOST="$host" >/dev/null 2>&1
fi

exec "$dir/herdr_focus.sh" "" "$tab"

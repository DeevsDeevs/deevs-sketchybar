#!/usr/bin/env bash

# Runs a herdr command on a remote host.
#   $1   ssh alias
#   $@   herdr arguments, e.g. `agent list`
#
# A plain ssh never sources the interactive rc, so a herdr installed by a version
# manager is not on PATH and the host reads as "no agents" while agents run on it.
# Going through `$SHELL -ic` does find it, at 2.1s a call — a price the widget would
# otherwise pay on every poll. Resolving the path once per host and remembering it
# brings a call down to a single bare ssh, about 120ms.

set -u
export PATH="/usr/bin:/bin:$PATH"

host="${1:-}"
[ -n "$host" ] || exit 0
shift

# ConnectTimeout bounds only the handshake; ServerAlive deadlines the live session,
# which is what a lapsed Tailscale grant otherwise hangs on.
ssh_run() {
    ssh -o BatchMode=yes -o ConnectTimeout=4 \
        -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
        -- "$host" "$1" 2>/dev/null
}

cache="${TMPDIR:-/tmp}/sketchybar-herdr-path-$(printf '%s' "$host" | tr -c 'A-Za-z0-9._-' '_')"

quoted=""
for arg in "$@"; do quoted="$quoted $(printf '%q' "$arg")"; done

remote_path=""
[ -r "$cache" ] && read -r remote_path < "$cache"

if [ -n "$remote_path" ]; then
    out="$(ssh_run "$remote_path$quoted")"
    status=$?
    # Any reply, or an ssh that could not connect at all, is final. Re-resolving on
    # an unreachable host would spend 2.1s on every poll while it stays down.
    if [ -n "$out" ] || [ "$status" -ne 0 ]; then
        [ -n "$out" ] && printf '%s\n' "$out"
        exit "$status"
    fi
fi

remote_path="$(ssh_run '$SHELL -ic "command -v herdr"' | tr -d '\r' | head -1)"
[ -n "$remote_path" ] || exit 1
# Atomic: a plain `>` truncates first, and a concurrent poll reading right then gets an
# empty path and falls back to the slow resolve.
printf '%s\n' "$remote_path" > "$cache.$$" && mv -f "$cache.$$" "$cache"

ssh_run "$remote_path$quoted"

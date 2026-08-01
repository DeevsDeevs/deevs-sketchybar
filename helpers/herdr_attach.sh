#!/usr/bin/env bash

# Brings a remote host's herdr up in front of you, opening it if it is not running.
#   $1  ssh alias
#   $2  pane id on that host (optional)
#
# In its own terminal window rather than a tab inside the local herdr: herdr refuses
# to start inside a herdr-managed pane — "nested herdr is disabled by default" — and
# the experimental flag that lifts that would leave both sessions answering to the
# same prefix key, with no send-prefix binding to tell them apart.

set -u
export PATH="/usr/bin:/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
RAISE="$DIR/raise/bin/raise"

host="${1:-}"
pane="${2:-}"
[ -n "$host" ] || exit 0
title="herdr@$host"

# Backgrounded: the far side's focus gates nothing here, and connecting takes longer.
[ -n "$pane" ] && "$DIR/herdr_remote.sh" "$host" agent focus "$pane" >/dev/null 2>&1 &

# Open it in whichever terminal is already hosting local herdr, rather than naming
# one: ghostty, iTerm, kitty and wezterm all host it equally.
app=""
for pid in $(pgrep -x herdr 2>/dev/null); do
    cur="$pid"
    for _ in 1 2 3 4 5 6 7 8; do
        ppid="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
        case "$ppid" in ('' | 0 | 1) break ;; esac
        comm="$(ps -o comm= -p "$ppid" 2>/dev/null)"
        case "$comm" in
            *.app/Contents/MacOS/*) app="${comm%%.app/*}.app"; break ;;
        esac
        cur="$ppid"
    done
    [ -n "$app" ] && break
done
[ -n "$app" ] || exit 0

# Already open somewhere? A terminal runs as several processes and any of them may
# own the window, so every one is asked. --tab-titled only raises on a hit, so a
# miss here does not drag focus to an unrelated window.
for pid in $(pgrep -f "$app/Contents/MacOS/" 2>/dev/null); do
    "$RAISE" "$pid" --tab-titled "$title" 2>/dev/null && exit 0
done

open -na "$app" --args -e "$DIR/herdr_remote_window.sh" "$host"

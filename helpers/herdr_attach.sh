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

# Backgrounded: the far side's focus gates nothing here, and connecting takes longer.
[ -n "$pane" ] && "$DIR/herdr_remote.sh" "$host" agent focus "$pane" >/dev/null 2>&1 &

# Walks up to the first ancestor living inside an .app bundle, printing "<pid> <bundle>".
# Nothing is named outright: ghostty, iTerm, kitty and wezterm all host herdr equally.
app_ancestor() {
    cur="$1"
    for _ in 1 2 3 4 5 6 7 8; do
        ppid="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
        case "$ppid" in ('' | 0 | 1) return 1 ;; esac
        comm="$(ps -o comm= -p "$ppid" 2>/dev/null)"
        case "$comm" in
            *.app/Contents/MacOS/*)
                printf '%s %s.app\n' "$ppid" "${comm%%.app/*}"
                return 0
                ;;
        esac
        cur="$ppid"
    done
    return 1
}

# Already connected? Raise that window rather than dialling the host a second time.
# Found by its client process, not by a tab title: `open -na` hands every remote window
# an app instance of its own holding a single window, and a lone window has no tab bar
# for AX to report, so a title search matched nothing and each click opened one more.
for pid in $(pgrep -f "herdr --remote $host" 2>/dev/null); do
    found="$(app_ancestor "$pid")" || continue
    term="${found%% *}"
    # Activating an app whose window sits on another space raises it for a frame before
    # focus falls back, so travel there first — the same step herdr_focus.sh takes.
    if command -v yabai >/dev/null 2>&1; then
        space="$(yabai -m query --windows 2>/dev/null |
            jq -r --argjson pid "$term" \
                'map(select(.pid == $pid and (."is-minimized" | not))) | .[0].space // empty' 2>/dev/null)"
        [ -n "$space" ] && yabai -m space --focus "$space" >/dev/null 2>&1
    fi
    "$RAISE" "$term" && exit 0
done

# Not connected yet. Open it in whichever terminal is already hosting the local herdr.
app=""
for pid in $(pgrep -x herdr 2>/dev/null); do
    found="$(app_ancestor "$pid")" && { app="${found#* }"; break; }
done
[ -n "$app" ] || exit 0

open -na "$app" --args -e "$DIR/herdr_remote_window.sh" "$host"

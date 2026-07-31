#!/usr/bin/env bash

# Focuses a herdr pane and raises the terminal showing it.
#   $1  pane id
#
# `herdr agent focus` switches the pane inside herdr's own session but never raises
# the window, so clicking the bar from another app leaves you looking at that app
# with the right pane selected behind it.
#
# The terminal is found by walking up from a herdr process to the first ancestor
# living in an .app bundle, rather than naming one: ghostty, iTerm, kitty and
# wezterm all host it equally and none of them belong hardcoded in a shared config.

set -u
export PATH="/usr/bin:/bin:$PATH"

pane="${1:-}"
[ -n "$pane" ] || exit 0

herdr agent focus "$pane" >/dev/null 2>&1

app=""
for pid in $(pgrep -x herdr 2>/dev/null); do
    cur="$pid"
    for _ in 1 2 3 4 5 6 7 8; do
        ppid="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
        case "$ppid" in ('' | 0 | 1) break ;; esac
        case "$(ps -o comm= -p "$ppid" 2>/dev/null)" in
            *.app/Contents/MacOS/*)
                app="$(ps -o comm= -p "$ppid" 2>/dev/null)"
                app="${app%%.app/*}.app"
                break
                ;;
        esac
        cur="$ppid"
    done
    [ -n "$app" ] && break
done

[ -n "$app" ] && open -a "$app" 2>/dev/null
exit 0

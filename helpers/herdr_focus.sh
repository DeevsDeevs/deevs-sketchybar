#!/usr/bin/env bash

# Focuses a herdr pane, then puts the terminal showing it in front of you.
#   $1  pane id (optional — herdr_attach.sh calls this purely to raise)
#   $2  tab index to force (optional — skips discovery entirely)
#
# `herdr agent focus` switches the pane inside herdr's own session and stops there,
# so without this a click from another app selects the right pane behind whatever
# you were already looking at.
#
# Budgeted to feel instant. Discovering the terminal and its tab costs about a
# second, so it happens once and the answer is cached; a warm click is ~80ms.

set -u
export PATH="/usr/bin:/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
RAISE="$DIR/raise/bin/raise"
CACHE="${TMPDIR:-/tmp}/sketchybar-herdr-focus"

pane="${1:-}"
forced_tab="${2:-}"
# Backgrounded: switching the pane and raising the window do not depend on each
# other, and serialising them adds herdr's round trip to every click.
[ -n "$pane" ] && herdr agent focus "$pane" >/dev/null 2>&1 &

# --- which terminal is hosting herdr -----------------------------------------
# Walk up from a herdr process to the first ancestor inside an .app bundle, rather
# than naming one: ghostty, iTerm, kitty and wezterm all host it equally.
find_terminal() {
    for pid in $(pgrep -x herdr 2>/dev/null); do
        cur="$pid"
        for _ in 1 2 3 4 5 6 7 8; do
            ppid="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
            case "$ppid" in ('' | 0 | 1) break ;; esac
            case "$(ps -o comm= -p "$ppid" 2>/dev/null)" in
                *.app/Contents/MacOS/*) echo "$ppid"; return 0 ;;
            esac
            cur="$ppid"
        done
    done
    return 1
}

term_pid=""
tab_title=""
if [ -r "$CACHE" ]; then
    IFS='	' read -r term_pid tab_title < "$CACHE" || true
    kill -0 "${term_pid:-0}" 2>/dev/null || { term_pid=""; tab_title=""; }
fi
[ -n "$term_pid" ] || term_pid="$(find_terminal || true)"
[ -n "$term_pid" ] || exit 0

# --- go to its space ----------------------------------------------------------
# Activating an app whose window is on another space raises it for a frame before
# focus falls back. yabai's window ids go stale between query and focus, but the
# space number it reports is good enough to switch to.
if command -v yabai >/dev/null 2>&1; then
    space="$(yabai -m query --windows 2>/dev/null |
        jq -r --argjson pid "$term_pid" \
            'map(select(.pid == $pid and (."is-minimized" | not))) | .[0].space // empty' 2>/dev/null)"
    [ -n "$space" ] && yabai -m space --focus "$space" >/dev/null 2>&1
fi

if [ -n "$forced_tab" ]; then
    "$RAISE" "$term_pid" --tab "$forced_tab"
    exit 0
fi

# --- select the tab herdr is in ----------------------------------------------
# Warm path: the remembered title still names a tab, so press it and be done.
if [ -n "$tab_title" ] && "$RAISE" "$term_pid" --tab-titled "$tab_title" 2>/dev/null; then
    exit 0
fi

"$RAISE" "$term_pid"

# Cold path. herdr publishes no title of its own and its tty is absent from the
# accessibility tree, so its tab cannot be recognised — but a title written to that
# tty *does* reach it. Stamp a marker, read the tabs back to see which one moved,
# and put the old title straight back. Several herdr clients may be running and
# only one of them owns a tab here, hence trying each in turn.
before="$("$RAISE" "$term_pid" --tabs 2>/dev/null)"
[ "$(printf '%s' "$before" | grep -c .)" -gt 1 ] || exit 0

probe="herdr-locate-$$"
for tty in $(for p in $(pgrep -x herdr 2>/dev/null); do
                 t="$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
                 [ -n "$t" ] && [ "$t" != "??" ] && echo "$t"
             done | sort -u); do
    [ -w "/dev/$tty" ] || continue
    printf '\033]0;%s\007' "$probe" > "/dev/$tty" 2>/dev/null || continue
    sleep 0.2

    index="$("$RAISE" "$term_pid" --tabs 2>/dev/null | grep -n -x -F "$probe" | head -1 | cut -d: -f1)"
    original="$(printf '%s' "$before" | sed -n "${index:-0}p")"
    [ -n "$original" ] && printf '\033]0;%s\007' "$original" > "/dev/$tty" 2>/dev/null

    if [ -n "$index" ] && [ -n "$original" ]; then
        printf '%s\t%s\n' "$term_pid" "$original" > "$CACHE"
        "$RAISE" "$term_pid" --tab "$index"
        exit 0
    fi
done

exit 0

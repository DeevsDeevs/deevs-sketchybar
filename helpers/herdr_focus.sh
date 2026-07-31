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

# No pane is legitimate: herdr_attach.sh calls this purely to raise the terminal.
pane="${1:-}"
tab="${2:-}"
[ -n "$pane" ] && herdr agent focus "$pane" >/dev/null 2>&1

app=""
term_pid=""
for pid in $(pgrep -x herdr 2>/dev/null); do
    cur="$pid"
    for _ in 1 2 3 4 5 6 7 8; do
        ppid="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')"
        case "$ppid" in ('' | 0 | 1) break ;; esac
        case "$(ps -o comm= -p "$ppid" 2>/dev/null)" in
            *.app/Contents/MacOS/*)
                app="$(ps -o comm= -p "$ppid" 2>/dev/null)"
                app="${app%%.app/*}.app"
                term_pid="$ppid"
                break
                ;;
        esac
        cur="$ppid"
    done
    [ -n "$app" ] && break
done

# Go to the space first. Activating an app whose window is on another space raises it
# for a frame and then focus falls back to where you were — measured as ghostty at
# +1s and the previous app again at +2s. yabai's window ids go stale between query
# and focus, but the space number it reports is good enough to switch to.
if [ -n "$term_pid" ] && command -v yabai >/dev/null 2>&1; then
    space="$(yabai -m query --windows 2>/dev/null |
        jq -r --argjson pid "$term_pid" \
            'map(select(.pid == $pid and (."is-minimized" | not))) | .[0].space // empty' 2>/dev/null)"
    current="$(yabai -m query --spaces 2>/dev/null |
        jq -r 'map(select(."has-focus")) | .[0].index // empty' 2>/dev/null)"
    if [ -n "$space" ] && [ "$space" != "$current" ]; then
        yabai -m space --focus "$space" >/dev/null 2>&1
        sleep 0.2
    fi
fi

# Activate the exact process, not the bundle. A terminal commonly runs as several
# processes at once and `open -a` activates whichever the OS picks, which is
# regularly not the one hosting herdr: the app comes forward showing someone else's
# window. Needs Accessibility, which sketchybar already holds for the menus helper.
if [ -n "$term_pid" ]; then
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $term_pid) to true" \
        >/dev/null 2>&1
else
    [ -n "$app" ] && open -a "$app" 2>/dev/null
fi

# Raising the window shows whichever tab was already selected. herdr publishes no
# title to the terminal and its tty is not in the accessibility tree, so there is
# nothing to match a tab on — the index has to be configured.
if [ -n "$tab" ] && [ -n "$term_pid" ]; then
    osascript >/dev/null 2>&1 <<OSA
tell application "System Events"
  tell (first process whose unix id is $term_pid)
    tell (first UI element of window 1 whose role is "AXTabGroup")
      click radio button $tab
    end tell
  end tell
end tell
OSA
fi

exit 0

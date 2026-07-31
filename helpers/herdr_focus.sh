#!/usr/bin/env bash

# Focuses a herdr pane, then puts the terminal showing it in front of you.
#   $1  pane id (optional — herdr_attach.sh calls this purely to raise)
#   $2  tab index to force (optional — skips discovery)
#
# `herdr agent focus` switches the pane inside herdr's own session and stops there,
# so without this a click from another app selects the right pane behind whatever
# you were already looking at.

set -u
export PATH="/usr/bin:/bin:$PATH"

pane="${1:-}"
forced_tab="${2:-}"
[ -n "$pane" ] && herdr agent focus "$pane" >/dev/null 2>&1

# --- which terminal is hosting herdr -----------------------------------------
# Walk up from a herdr process to the first ancestor inside an .app bundle, rather
# than naming one: ghostty, iTerm, kitty and wezterm all host it equally and none
# of them belong hardcoded in a config other people run.
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

# --- go to its space, then raise it ------------------------------------------
# Activating an app whose window is on another space raises it for a frame before
# focus falls back. yabai's window ids go stale between query and focus, but the
# space number it reports is good enough to switch to.
if [ -n "$term_pid" ] && command -v yabai >/dev/null 2>&1; then
    space="$(yabai -m query --windows 2>/dev/null |
        jq -r --argjson pid "$term_pid" \
            'map(select(.pid == $pid and (."is-minimized" | not))) | .[0].space // empty' 2>/dev/null)"
    current="$(yabai -m query --spaces 2>/dev/null |
        jq -r 'map(select(."has-focus")) | .[0].index // empty' 2>/dev/null)"
    if [ -n "$space" ] && [ -n "$current" ] && [ "$space" != "$current" ]; then
        yabai -m space --focus "$space" >/dev/null 2>&1
        sleep 0.2
    fi
fi

# Activate the exact process, not the bundle: a terminal commonly runs as several
# processes and the OS picks whichever it likes, bringing forward someone else's
# window. Needs Accessibility, which sketchybar already holds for the menus helper.
if [ -n "$term_pid" ]; then
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $term_pid) to true" \
        >/dev/null 2>&1
else
    [ -n "$app" ] && open -a "$app" 2>/dev/null
    exit 0
fi

# --- select the tab herdr is in ----------------------------------------------
# Raising a window shows whichever tab was last on top, so a shared window lands
# you on a neighbour's session.
tab_names() {
    osascript 2>/dev/null <<OSA
tell application "System Events"
  tell (first process whose unix id is $term_pid)
    tell (first UI element of window 1 whose role is "AXTabGroup")
      set out to ""
      repeat with r in radio buttons
        set out to out & (name of r) & linefeed
      end repeat
      return out
    end tell
  end tell
end tell
OSA
}

click_tab() {
    osascript >/dev/null 2>&1 <<OSA
tell application "System Events"
  tell (first process whose unix id is $term_pid)
    tell (first UI element of window 1 whose role is "AXTabGroup")
      click radio button $1
    end tell
  end tell
end tell
OSA
}

if [ -n "$forced_tab" ]; then
    click_tab "$forced_tab"
    exit 0
fi

before="$(tab_names)"
# One tab, or a terminal without a tab group: nothing to choose between.
[ "$(printf '%s' "$before" | grep -c .)" -gt 1 ] || exit 0

# herdr publishes no title of its own and its tty is absent from the accessibility
# tree, so the tab cannot be recognised — but a title written to that tty *does*
# reach it. Stamp a marker, read the tabs back, and put the old title where it was.
# Several herdr clients can be running; only one of them owns a tab here.
probe="herdr-locate-$$"
for tty in $(for p in $(pgrep -x herdr 2>/dev/null); do
                 t="$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
                 [ -n "$t" ] && [ "$t" != "??" ] && echo "$t"
             done | sort -u); do
    [ -w "/dev/$tty" ] || continue
    printf '\033]0;%s\007' "$probe" > "/dev/$tty" 2>/dev/null || continue
    sleep 0.25

    index="$(tab_names | grep -n -x -F "$probe" | head -1 | cut -d: -f1)"
    original="$(printf '%s' "$before" | sed -n "${index:-0}p")"
    [ -n "$original" ] && printf '\033]0;%s\007' "$original" > "/dev/$tty" 2>/dev/null

    if [ -n "$index" ]; then
        click_tab "$index"
        exit 0
    fi
done

exit 0

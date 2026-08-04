#!/bin/sh

# Holds the Mac awake. Tracked by pid rather than `pgrep caffeinate`, because other
# things run caffeinate too — Claude Code keeps one alive while it works — and adopting
# someone else's would light the cup for a state this widget cannot turn off.
#
#   status        prints "off", "on inf", or "on <seconds-left>"
#   on [minutes]  hold awake, indefinitely or for a while
#   off           release
#
# -d as well as -i: without it the screen still sleeps, which is not what clicking a
# coffee cup means.

set -u
export PATH="/usr/bin:/bin:$PATH"

STATE="${TMPDIR:-/tmp}/sketchybar-caffeine"

held() {
    [ -r "$STATE" ] || return 1
    read -r pid ends < "$STATE" || return 1
    kill -0 "$pid" 2>/dev/null
}

release() {
    held && kill "$pid" 2>/dev/null
    rm -f "$STATE"
}

case "${1:-status}" in
    status)
        if held; then
            # A timed hold exits on its own, so the pid dying is what ends it; this is
            # only for the countdown.
            [ "$ends" = "inf" ] && echo "on inf" || echo "on $((ends - $(date +%s)))"
        else
            echo off
        fi
        ;;
    off)
        release
        ;;
    on)
        release
        minutes="${2:-}"
        if [ -n "$minutes" ]; then
            caffeinate -di -t "$((minutes * 60))" &
            printf '%s %s\n' "$!" "$(($(date +%s) + minutes * 60))" > "$STATE"
        else
            caffeinate -di &
            printf '%s inf\n' "$!" > "$STATE"
        fi
        ;;
esac

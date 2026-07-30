#!/usr/bin/env bash

# Pushes Session state into the bar as session_update events.
#
# The widget used to pull this with sbar.exec on a timer, but those callbacks
# stop arriving after a few minutes of polling and the chip freezes on whatever
# it last saw — a finished block kept counting down, a started one never
# appeared. Pushing from a single long-lived process is the same shape as
# media_stream.sh and needs no callbacks at all.
#
# Only a coarse resync is sent; widgets/session.lua counts the seconds down
# itself between updates.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY="$DIR/session_query.sh"
[ -x "$QUERY" ] || exit 0

while :; do
  # Detached from sketchybar, so nothing else would ever reap this: without the
  # check it keeps polling (and spawning a handful of processes every 2s) long
  # after the bar is gone.
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  line="$("$QUERY" current)"

  # Poll rate follows the state. Only a running block needs second-level
  # freshness; idle needs to notice a new one starting, and once Session turns
  # out to be absent it cannot appear without a relaunch, which restarts this.
  case "$line" in
    RUN*)
      nap=2
      IFS=$'\t' read -r _ left total kind title <<<"$line"
      IFS=$'\t' read -r today_n today_min <<<"$("$QUERY" today)"
      sketchybar --trigger session_update \
        STATE=run LEFT="${left:-0}" TOTAL="${total:-0}" KIND="${kind:-focus}" \
        TODAY_N="${today_n:-0}" TODAY_MIN="${today_min:-0}" TITLE="${title:-}" \
        >/dev/null 2>&1
      ;;
    NODB*)
      nap=300
      sketchybar --trigger session_update STATE=absent >/dev/null 2>&1
      ;;
    IDLE)
      nap=4
      IFS=$'\t' read -r today_n today_min <<<"$("$QUERY" today)"
      sketchybar --trigger session_update STATE=idle \
        TODAY_N="${today_n:-0}" TODAY_MIN="${today_min:-0}" >/dev/null 2>&1
      ;;
    *)
      # Only an explicit IDLE clears the chip. Anything else means the query
      # itself broke, and asserting "idle" there blanks a running session.
      nap=10
      ;;
  esac

  sleep "${nap:-2}"
done

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
  line="$("$QUERY" current)"

  case "$line" in
    RUN*)
      IFS=$'\t' read -r _ left total kind title <<<"$line"
      IFS=$'\t' read -r today_n today_min <<<"$("$QUERY" today)"
      sketchybar --trigger session_update \
        STATE=run LEFT="${left:-0}" TOTAL="${total:-0}" KIND="${kind:-focus}" \
        TODAY_N="${today_n:-0}" TODAY_MIN="${today_min:-0}" TITLE="${title:-}" \
        >/dev/null 2>&1
      ;;
    NODB*)
      sketchybar --trigger session_update STATE=absent >/dev/null 2>&1
      ;;
    *)
      IFS=$'\t' read -r today_n today_min <<<"$("$QUERY" today)"
      sketchybar --trigger session_update STATE=idle \
        TODAY_N="${today_n:-0}" TODAY_MIN="${today_min:-0}" >/dev/null 2>&1
      ;;
  esac

  sleep 2
done

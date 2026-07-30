#!/usr/bin/env bash

# Pushes Session state into the bar as session_update events.
# Push, don't poll: sbar.exec callbacks stop arriving after minutes of
# sustained polling. widgets/session.lua counts seconds down between resyncs.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY="$DIR/session_query.sh"
[ -x "$QUERY" ] || exit 0

while :; do
  # Detached from sketchybar: exit when the bar is gone, or this polls forever.
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  line="$("$QUERY" current)"

  # Poll rate follows the state; NODB can't change without a relaunch of this.
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
      # Only explicit IDLE clears the chip; a broken query must not blank a running session.
      nap=10
      ;;
  esac

  sleep "${nap:-2}"
done

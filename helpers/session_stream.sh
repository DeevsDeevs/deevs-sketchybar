#!/usr/bin/env bash

# Push, don't poll: sbar.exec callbacks stop arriving after minutes of sustained polling.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY="$DIR/session_query.sh"
[ -x "$QUERY" ] || exit 0

while :; do
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  line="$("$QUERY" current)"

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
      nap=10
      ;;
  esac

  sleep "${nap:-2}"
done

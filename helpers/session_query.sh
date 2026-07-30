#!/usr/bin/env bash

# Session.app state for widgets/session.lua.
#   current -> "RUN\t<seconds left>\t<total seconds>\t<focus|rest>\t<title>"
#              "IDLE" when nothing is running, "NODB" when Session isn't here
#   today   -> "<focus blocks>\t<focused minutes>"
# The sqlite is history only; the live session is the RunningSession pref of the
# group container, read via `defaults export` (the plist on disk lags).
# Title is emitted last so an embedded tab can't shift the fields.

set -u

# macOS tools first: a nix/devbox PATH shadows base64 and date (GNU has no -j).
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

GROUP="$HOME/Library/Group Containers/98JSB2MQB3.group.com.philipyoungg.translucent"
DB="${SESSION_DB:-$GROUP/Session.sqlite}"
DOMAIN="${SESSION_DOMAIN:-$GROUP/Library/Preferences/98JSB2MQB3.group.com.philipyoungg.translucent}"

# NODB (Session not installed) hides the widget; IDLE keeps an empty ring.
if [ ! -r "$DB" ] && [ ! -r "$DOMAIN.plist" ]; then
  [ "${1:-current}" = "current" ] && printf 'NODB\n'
  exit 0
fi

case "${1:-current}" in
  current)
    json="$(defaults export "$DOMAIN" - 2>/dev/null \
      | plutil -extract RunningSession raw -o - - 2>/dev/null \
      | base64 -d 2>/dev/null)"
    if [ -z "$json" ] || ! command -v jq >/dev/null 2>&1; then
      printf 'IDLE\n'
      exit 0
    fi

    # floor: pause_buffer turns float after a pause/resume; shell arithmetic can't parse it.
    IFS=$'\t' read -r state dur buf start title <<EOF
$(printf '%s' "$json" | jq -r '[(.state//""), (.duration_second//0|floor), (.pause_buffer//0|floor), (.start_date//""), (.title//"")] | @tsv')
EOF

    # Paused/unknown states read as IDLE, not a countdown that keeps draining.
    case "${state:-}" in
      session) kind=focus ;;
      rest)    kind=rest ;;
      *)       printf 'IDLE\n'; exit 0 ;;
    esac

    # BSD date -f is exact-match: strip fractional seconds or parsing fails.
    start="${start%%.*}"
    case "$start" in *Z) ;; *) start="${start}Z" ;; esac
    started="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${start:-}" +%s 2>/dev/null || true)"
    if [ -z "$started" ]; then
      printf 'IDLE\n'
      exit 0
    fi

    left=$(( started + dur + buf - $(date +%s) ))
    if [ "$left" -le 0 ]; then
      printf 'IDLE\n'
    else
      printf 'RUN\t%s\t%s\t%s\t%s\n' "$left" "$dur" "$kind" "$title"
    fi
    ;;

  today)
    [ -r "$DB" ] || exit 0
    # ZSTARTDATE is Core Data epoch: unix minus 978307200.
    sqlite3 -readonly "file:$DB?mode=ro" \
      "SELECT count(*) || char(9) || cast(coalesce(sum(ZENDDATE-ZSTARTDATE)/60,0) as int)
       FROM ZSESSIONTASK
       WHERE ZTYPE LIKE '%Focus%'
         AND date(ZSTARTDATE+978307200,'unixepoch','localtime') = date('now','localtime');" 2>/dev/null
    ;;
esac

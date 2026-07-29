#!/usr/bin/env bash

# Session.app state for widgets/session.lua.
#
#   current -> "RUN\t<seconds left>\t<total seconds>\t<focus|rest>\t<title>"
#              "IDLE" when nothing is running, "NODB" when Session isn't here
#   today   -> "<focus blocks>\t<focused minutes>"
#
# The running session is NOT in the sqlite: Session only writes a task row once
# the block finishes, so the database is history. The live one lives under the
# RunningSession key of the group container's preferences, as a JSON blob
# stored in a data field. Read it through `defaults export` rather than off
# disk, because Session writes via NSUserDefaults and the file lags behind.
#
# Session keeps Core Data timestamps (unix minus 978307200) in the sqlite, and
# ISO-8601 UTC in the plist. The title is emitted last so a tab inside an
# intent can't shift the fields before it.

set -u

# macOS tools first: a nix/devbox PATH shadows base64 (GNU wants -d, not -D)
# and date (GNU has no -j), both of which are used below.
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

GROUP="$HOME/Library/Group Containers/98JSB2MQB3.group.com.philipyoungg.translucent"
DB="${SESSION_DB:-$GROUP/Session.sqlite}"
DOMAIN="${SESSION_DOMAIN:-$GROUP/Library/Preferences/98JSB2MQB3.group.com.philipyoungg.translucent}"

# NODB (no Session installed) is distinct from IDLE (installed, nothing
# running): the widget hides itself entirely for the former and keeps an empty
# ring for the latter.
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

    IFS=$'\t' read -r state dur buf start title <<EOF
$(printf '%s' "$json" | jq -r '[(.state//""), (.duration_second//0), (.pause_buffer//0), (.start_date//""), (.title//"")] | @tsv')
EOF

    # Only states we have actually observed count as running; a paused or
    # unknown state falls back to the empty ring rather than a countdown that
    # would keep draining while the timer is stopped.
    case "${state:-}" in
      session) kind=focus ;;
      rest)    kind=rest ;;
      *)       printf 'IDLE\n'; exit 0 ;;
    esac

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
    sqlite3 -readonly "file:$DB?mode=ro" \
      "SELECT count(*) || char(9) || cast(coalesce(sum(ZENDDATE-ZSTARTDATE)/60,0) as int)
       FROM ZSESSIONTASK
       WHERE ZTYPE LIKE '%Focus%'
         AND date(ZSTARTDATE+978307200,'unixepoch','localtime') = date('now','localtime');" 2>/dev/null
    ;;
esac

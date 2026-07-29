#!/usr/bin/env bash

# Session.app state for widgets/session.lua.
#
#   current -> "<seconds left>\t<total seconds>\t<type>\t<name>" for the running
#              session, nothing at all when idle
#   today   -> "<focus blocks>\t<focused minutes>"
#
# Session keeps a readable sqlite in its shared group container ("translucent"
# is the app's original name) and stores Core Data timestamps, which are unix
# time minus 978307200. The name is emitted last so a tab or pipe inside an
# intent can't shift the fields before it.

set -u
DB="${SESSION_DB:-$HOME/Library/Group Containers/98JSB2MQB3.group.com.philipyoungg.translucent/Session.sqlite}"
# No Session installed is a definite "nothing running", not a lost reply.
if [ ! -r "$DB" ]; then
  [ "${1:-current}" = "current" ] && printf 'IDLE\n'
  exit 0
fi

query() { sqlite3 -readonly "file:$DB?mode=ro" "$1" 2>/dev/null; }

case "${1:-current}" in
  current)
    # Answer with a sentinel rather than silence, so the widget can tell "no
    # session is running" apart from "the reply never arrived".
    row="$(query "SELECT cast(ZENDDATE - (strftime('%s','now') - 978307200) as int)
             || char(9) || cast(ZENDDATE - ZSTARTDATE as int)
             || char(9) || coalesce(ZTYPE,'')
             || char(9) || coalesce(ZNAME,'')
           FROM ZSESSIONTASK
           WHERE ZENDDATE > (strftime('%s','now') - 978307200)
           ORDER BY ZENDDATE DESC LIMIT 1;")"
    if [ -n "$row" ]; then printf 'RUN\t%s\n' "$row"; else printf 'IDLE\n'; fi
    ;;
  today)
    query "SELECT count(*) || char(9) || cast(coalesce(sum(ZENDDATE-ZSTARTDATE)/60,0) as int)
           FROM ZSESSIONTASK
           WHERE ZTYPE LIKE '%Focus%'
             AND date(ZSTARTDATE+978307200,'unixepoch','localtime') = date('now','localtime');"
    ;;
esac

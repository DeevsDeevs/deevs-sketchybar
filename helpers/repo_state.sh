#!/usr/bin/env bash

# One line of git state for the repo widget:
#   ok <branch|(detached)> <sha7> <dirty-count>
# Prints nothing at all when the path is not a usable repo — the "ok" marker is
# what lets the widget tell an answer from a failure, because SbarLua hands the
# callback a buffer it never NUL-terminates and a read can carry trailing memory.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

dir="${1:-}"
[ -n "$dir" ] || exit 1

# --no-optional-locks so a poller never takes index.lock away from the user's own
# git commands. --untracked-files=normal because status.showUntrackedFiles in a
# user's gitconfig otherwise silently changes the number.
git --no-optional-locks -C "$dir" status --porcelain=v2 --branch \
    --untracked-files=normal 2>/dev/null |
awk '$1=="#" && $2=="branch.oid"  { o=$3 }
     $1=="#" && $2=="branch.head" { h=$3 }
     $1!="#"                      { n++ }
     END { if (o=="") exit 1; print "ok", h, substr(o,1,7), n+0 }'

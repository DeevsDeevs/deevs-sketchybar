#!/usr/bin/env bash

# Everything the repo widget needs about one directory, in one tab-separated line:
#   ok<TAB>queried<TAB>root<TAB>branch|(detached)<TAB>sha7<TAB>dirty
#   no<TAB>queried                        -- not inside a git repo
#
# The queried directory is echoed back on purpose. SbarLua registers each exec
# callback with luaL_ref and unrefs it on reply, so refs are recycled and one
# command's output can be handed to a different command's callback — measured:
# a rev-parse for one repo returned another repo's path. The widget compares the
# echo against what it asked for and drops anything that does not match, so a
# crossed reply is inert rather than wrong.
#
# Resolving the root and reading its status in one process also halves the number
# of concurrent execs, which is what makes the collision likely in the first place.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

dir="${1:-}"
[ -n "$dir" ] || exit 1

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ]; then
    printf 'no\t%s\n' "$dir"
    exit 0
fi

# --no-optional-locks so a poller never takes index.lock away from the user's own
# git commands. --untracked-files=normal because status.showUntrackedFiles in a
# user's gitconfig otherwise silently changes the number.
git --no-optional-locks -C "$root" status --porcelain=v2 --branch \
    --untracked-files=normal 2>/dev/null |
awk -v d="$dir" -v r="$root" '
    $1=="#" && $2=="branch.oid"  { o=$3 }
    $1=="#" && $2=="branch.head" { h=$3 }
    $1!="#"                      { n++ }
    END {
        if (o=="") exit 1
        printf "ok\t%s\t%s\t%s\t%s\t%d\n", d, r, h, substr(o,1,7), n+0
    }'

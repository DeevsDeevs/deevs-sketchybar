#!/usr/bin/env bash

# Everything the repo widget needs about one directory, in one tab-separated line:
#
#   ok <queried> <root> <branch|(detached)> <sha7> <dirty> \
#      <staged> <unstaged> <untracked> <ahead> <behind> <upstream> <subject>
#   no <queried>                          -- not inside a git repo
#
# The queried directory is echoed back on purpose. SbarLua registers each exec
# callback with luaL_ref and unrefs it on reply, so refs are recycled and one
# command's output can be handed to a different command's callback — measured:
# a rev-parse for one repo returned another repo's path. The widget compares the
# echo against what it asked for and drops anything that does not match, so a
# crossed reply is inert rather than wrong.
#
# Answering everything in one process also keeps the number of concurrent execs
# down, which is what makes that collision likely in the first place.

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
# user's gitconfig otherwise silently changes the numbers.
status="$(git --no-optional-locks -C "$root" status --porcelain=v2 --branch \
    --untracked-files=normal 2>/dev/null)"
[ -n "$status" ] || exit 1

# Tabs are the field separator, so a subject containing one would shift every
# later field. Newlines can't appear in %s but strip defensively.
subject="$(git --no-optional-locks -C "$root" log -1 --format=%s 2>/dev/null \
    | tr '\t\n' '  ')"

printf '%s\n' "$status" | awk -v d="$dir" -v r="$root" -v subj="$subject" '
    $1=="#" && $2=="branch.oid"      { oid=$3 }
    $1=="#" && $2=="branch.head"     { head=$3 }
    $1=="#" && $2=="branch.upstream" { up=$3 }
    # "+N -M" for ahead/behind; absent entirely when there is no upstream.
    $1=="#" && $2=="branch.ab"       { a=$3+0; b=$4+0 }
    # Tracked changes: "1"/"2" records carry a two-letter XY code, X staged and
    # Y unstaged. "u" is an unmerged path, which counts as both.
    $1=="1" || $1=="2" {
        n++
        split($2, xy, "")
        if (xy[1] != ".") s++
        if (xy[2] != ".") u++
    }
    $1=="u" { n++; s++; u++ }
    $1=="?" { n++; q++ }
    END {
        if (oid=="") exit 1
        printf "ok\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n",
            d, r, head, substr(oid,1,7), n+0, s+0, u+0, q+0, a+0, b+0,
            (up=="" ? "-" : up), subj
    }'

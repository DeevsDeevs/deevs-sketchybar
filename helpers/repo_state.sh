#!/usr/bin/env bash

# One tab-separated line of git state for the repo widget:
#
#   ok <queried> <root> <branch|(detached)> <sha7> <dirty> \
#      <staged> <unstaged> <untracked> <ahead> <behind> <upstream> <subject>
#   no <queried>                          -- not inside a git repo
#
# SbarLua recycles exec callback refs, so a reply can reach the wrong callback;
# echoing back the queried directory lets the widget drop crossed replies.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

dir="${1:-}"
[ -n "$dir" ] || exit 1

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ]; then
    printf 'no\t%s\n' "$dir"
    exit 0
fi

# --no-optional-locks: never take index.lock from the user's own git commands.
# --untracked-files=normal: a user's status.showUntrackedFiles must not skew counts.
status="$(git --no-optional-locks -C "$root" status --porcelain=v2 --branch \
    --untracked-files=normal 2>/dev/null)"
[ -n "$status" ] || exit 1

# Tabs are the field separator; strip tabs and newlines from the subject.
subject="$(git --no-optional-locks -C "$root" log -1 --format=%s 2>/dev/null \
    | tr '\t\n' '  ')"

printf '%s\n' "$status" | awk -v d="$dir" -v r="$root" -v subj="$subject" '
    $1=="#" && $2=="branch.oid"      { oid=$3 }
    $1=="#" && $2=="branch.head"     { head=$3 }
    $1=="#" && $2=="branch.upstream" { up=$3 }
    # "+N -M" for ahead/behind; absent entirely when there is no upstream.
    $1=="#" && $2=="branch.ab"       { a=$3+0; b=$4+0 }
    # "1"/"2" records carry XY (X staged, Y unstaged); "u" unmerged counts as both.
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

#!/usr/bin/env bash

# Prints the px available for the media text box between the left group and the
# notch, or nothing when there is no notch to avoid. $1 is what the media cluster
# needs besides the text (cover + eq bars).
#
# Needed because the text expands on hover and pushes the rest of the cluster
# right; a fixed width slides it under the notch as soon as enough space chips
# are open. The left group's width is only knowable at runtime, hence the query.

set -u
export PATH="/usr/bin:/bin:$PATH"

reserved="${1:-0}"

notch_left="$("$(dirname "$0")/notch.sh" | awk '{print $1}')"
[ -n "$notch_left" ] || exit 0

# front_app is the last item before media in the left group, and hovering media
# never moves it, so its right edge is a stable anchor.
edge="$(sketchybar --query front_app 2>/dev/null |
    jq -r '.bounding_rects | to_entries[0].value | (.origin[0] + .size[0]) | floor' 2>/dev/null)"
case "$edge" in ('' | *[!0-9]*) exit 0 ;; esac

avail=$(( notch_left - edge - reserved - 12 ))
[ "$avail" -lt 40 ] && avail=40
printf '%d\n' "$avail"

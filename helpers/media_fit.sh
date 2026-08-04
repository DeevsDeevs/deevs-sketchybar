#!/usr/bin/env bash

# Prints the px available for the media text box before the notch, or nothing when
# there is no notch to avoid.
#   $1  name of the cluster's last item (the one nearest the notch)
#   $2  px of text width currently applied, so an expanded cluster measures the
#       same as a collapsed one
#   $3  left edge of the notch, optional. Finding it costs an osascript that imports
#       AppKit, about 69ms, and it only moves when the displays do — so the caller
#       resolves it once and passes it here. Looked up when absent, which keeps this
#       script runnable on its own.
#
# Measured rather than estimated: the cover and the eq bars do not occupy what their
# configured widths suggest, and the room left of the notch shrinks with every space
# chip, so both ends of the sum have to come from the live bar.

set -u
export PATH="/usr/bin:/bin:$PATH"

last="${1:-}"
applied="${2:-0}"
notch_left="${3:-}"
[ -n "$last" ] || exit 0

[ -n "$notch_left" ] || notch_left="$("$(dirname "$0")/notch.sh" | awk '{print $1}')"
case "$notch_left" in ('' | *[!0-9]*) exit 0 ;; esac

edge="$(sketchybar --query "$last" 2>/dev/null |
    jq -r '.bounding_rects | to_entries[0].value | (.origin[0] + .size[0]) | floor' 2>/dev/null)"
case "$edge" in ('' | *[!0-9]*) exit 0 ;; esac

# A hidden item parks at -9999; nothing useful to measure from.
[ "$edge" -lt 0 ] && exit 0

avail=$(( notch_left - edge + applied - 16 ))
[ "$avail" -lt 40 ] && avail=40
printf '%d\n' "$avail"

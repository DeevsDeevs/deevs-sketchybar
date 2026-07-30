#!/usr/bin/env bash

# Prints "<notch-left> <notch-right>" in logical points for the built-in display,
# or nothing at all when there is no notch (external monitor, older Mac).
#
# NSScreen exposes the notch as the gap between the two auxiliary top areas, and
# returns zero-size rects when there is none — so an empty output is the honest
# answer for "no notch", not a failure. sketchybar 2.24 has no notch property of
# its own, which is why this exists.

set -u
export PATH="/usr/bin:/bin:$PATH"

osascript -l JavaScript -e '
ObjC.import("AppKit");
var s = $.NSScreen.screens.objectAtIndex(0);
var l = s.auxiliaryTopLeftArea, r = s.auxiliaryTopRightArea;
if (l.size.width > 0 && r.size.width > 0) {
  Math.round(l.origin.x + l.size.width) + " " + Math.round(r.origin.x);
} else {
  "";
}
' 2>/dev/null

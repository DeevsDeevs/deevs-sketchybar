#!/usr/bin/env bash

# Drives the media.eq.* bar cluster from cava.
#
# cava reads BlackHole, which receives a copy of everything you play: the
# audio_devices helper routes every output selection through a multi-output
# aggregate of <your device + BlackHole>, so this keeps working across device
# switches. Falls back to the default input when BlackHole isn't installed.
# Nix's cava defaults to pulseaudio, so portaudio is forced here.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

command -v cava >/dev/null 2>&1 || exit 0

# Deliberately NOT holding a single-instance lock here. A mkdir lock loses the
# startup race: start_sonar pkills the previous instance and spawns the next
# immediately, so the new mkdir runs before the dying one's EXIT trap releases
# it, and the replacement exits silently leaving no EQ at all. Overlapping
# instances are rare (they need system_woke and audio_route_changed to interleave)
# and self-heal on the next reload; no EQ does not.
BARS="${SONAR_BARS:-12}"
MAX_H="${SONAR_HEIGHT:-16}"   # px at full scale

SRC="auto"
if system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch"; then
  SRC="BlackHole 2ch"
fi

cfg="$(mktemp "${TMPDIR:-/tmp}/sonar-cava.XXXXXX")"
trap 'rm -f "$cfg"' EXIT HUP INT TERM
cat >"$cfg" <<EOF
[general]
bars = ${BARS}
framerate = 15
[input]
method = portaudio
source = ${SRC}
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = ${MAX_H}
EOF

# One batched --set per frame: heights plus a y_offset so bars grow upward
# from a common baseline (sketchybar backgrounds are vertically centered).
#
# cava emits frames whether or not anything is playing — its sleep_timer is
# disabled by default — so without the floor check below this forked a
# sketchybar process 15 times a second forever, writing heights into items that
# are not even drawn. Silence is every band at the floor, which is also what a
# non-whitelisted app playing looks like from here. One flat frame is still sent
# so the bars settle, then nothing until sound returns.
prev_flat=0

cava -p "$cfg" 2>/dev/null | while IFS= read -r line; do
  [ -z "$line" ] && continue
  args=()
  i=1
  flat=1
  IFS=';' read -ra vals <<<"$line"
  for v in "${vals[@]}"; do
    [ "$i" -gt "$BARS" ] && break
    case "$v" in (*[!0-9]*|"") v=0 ;; esac
    h=$((v < 2 ? 2 : v))
    [ "$h" -gt 2 ] && flat=0
    args+=(--set "media.eq.$i" background.height="$h" y_offset=$(( (h - MAX_H) / 2 )))
    i=$((i + 1))
  done
  [ ${#args[@]} -eq 0 ] && continue

  if [ "$flat" = 1 ]; then
    [ "$prev_flat" = 1 ] && continue
    prev_flat=1
  else
    prev_flat=0
  fi

  # A failing --set means the bar is gone; nothing left to draw into.
  sketchybar "${args[@]}" >/dev/null 2>&1 || exit 0
done

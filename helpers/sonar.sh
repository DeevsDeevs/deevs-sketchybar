#!/usr/bin/env bash

# Drives the media.eq.* bar cluster from cava.
#
# cava listens to the default INPUT device. For bars that follow your music
# instead of the room, install a loopback (BlackHole 2ch) and make it the
# input — see README. Nix's cava defaults to pulseaudio, so portaudio is
# forced here.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

command -v cava >/dev/null 2>&1 || exit 0

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
cava -p "$cfg" 2>/dev/null | while IFS= read -r line; do
  [ -z "$line" ] && continue
  args=()
  i=1
  IFS=';' read -ra vals <<<"$line"
  for v in "${vals[@]}"; do
    [ "$i" -gt "$BARS" ] && break
    case "$v" in (*[!0-9]*|"") v=0 ;; esac
    h=$((v < 2 ? 2 : v))
    args+=(--set "media.eq.$i" background.height="$h" y_offset=$(( (h - MAX_H) / 2 )))
    i=$((i + 1))
  done
  [ ${#args[@]} -eq 0 ] && continue
  sketchybar "${args[@]}" >/dev/null 2>&1 || exit 0
done

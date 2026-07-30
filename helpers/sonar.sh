#!/usr/bin/env bash

# Drives the media.eq.* bar cluster from cava.
# cava can only listen to an INPUT, hence the BlackHole loopback.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

command -v cava >/dev/null 2>&1 || exit 0

BARS="${SONAR_BARS:-12}"
MAX_H="${SONAR_HEIGHT:-16}"

SRC="auto"
if system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch"; then
  SRC="BlackHole 2ch"
fi

# No single-instance lock on purpose: media.lua pkills and respawns this before the
# old EXIT trap frees one, so the replacement would exit and leave no EQ.
# nix's cava defaults to pulseaudio, hence method = portaudio below.
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

# sketchybar backgrounds are vertically centered; y_offset grows bars up from a common baseline.
# cava keeps emitting frames in silence, so send one flat frame then stop until sound
# returns — otherwise this forks sketchybar 15x/sec forever.
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

  sketchybar "${args[@]}" >/dev/null 2>&1 || exit 0
done

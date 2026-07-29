#!/usr/bin/env bash

# Streams a cava band into the "media.sonar" graph item.
# Needs: cava, and a loopback input (e.g. BlackHole 2ch) to hear system audio.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

command -v cava >/dev/null 2>&1 || exit 0

# Tap BlackHole only when the CURRENT output routes through it (a
# Multi-Output/aggregate device) — a plain device (AirPods, speakers)
# bypasses BlackHole, so fall back to ambient mic instead of silence.
SRC="auto"
default_out="$(system_profiler SPAudioDataType 2>/dev/null | awk '
  /^        [A-Za-z]/ { name=$0; sub(/^ +/,"",name); sub(/:$/,"",name) }
  /Default Output Device: Yes/ { print name; exit }')"
case "$default_out" in
  *Multi-Output*|*Aggregate*|*BlackHole*) SRC="BlackHole 2ch" ;;
esac

cfg="$(mktemp "${TMPDIR:-/tmp}/sonar-cava.XXXXXX")"
trap 'rm -f "$cfg"' EXIT HUP INT TERM
cat >"$cfg" <<EOF
[general]
bars = 1
framerate = 12
[input]
method = portaudio
source = ${SRC}
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
EOF

cava -p "$cfg" 2>/dev/null | while IFS=';' read -r v _; do
  case "$v" in (*[!0-9]*|"") continue ;; esac
  sketchybar --push media.sonar "$(awk -v x="$v" 'BEGIN{printf "%.2f", x/100}')" 2>/dev/null || exit 0
done

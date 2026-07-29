#!/usr/bin/env bash

# Streams system-audio level into the "media.sonar" graph item.
# Primary: audiotap (CoreAudio process tap, macOS 14.4+ — no loopback driver,
# follows any output device). Fallback: cava on the default input (mic).
# audiotap needs the "System Audio Recording" privacy permission once.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"

DIR="$(cd "$(dirname "$0")" && pwd)"
TAP="$DIR/audiotap/bin/audiotap"

if [ -x "$TAP" ] && "$TAP" --probe >/dev/null 2>&1; then
  "$TAP" | while IFS= read -r v; do
    sketchybar --push media.sonar "$v" 2>/dev/null || exit 0
  done
  exit 0
fi

command -v cava >/dev/null 2>&1 || exit 0

cfg="$(mktemp "${TMPDIR:-/tmp}/sonar-cava.XXXXXX")"
trap 'rm -f "$cfg"' EXIT HUP INT TERM
cat >"$cfg" <<EOF
[general]
bars = 1
framerate = 12
[input]
method = portaudio
source = auto
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

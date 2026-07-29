#!/usr/bin/env bash

# deevs-sketchybar installer: builds C helpers, checks dependencies.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\033[1;32m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

command -v sketchybar >/dev/null || { warn "sketchybar not found — install it first (brew/nix)"; exit 1; }
command -v clang >/dev/null || { warn "clang not found — install Xcode command line tools"; exit 1; }
# sketchybarrc is a lua script and macOS ships no lua: without it the bar comes
# up completely empty, with the failure buried in sketchybar's log.
command -v lua >/dev/null || { warn "lua not found — the config is a lua script (brew install lua)"; exit 1; }
command -v jq >/dev/null || { warn "jq not found — media and session need it (brew install jq)"; exit 1; }
command -v git >/dev/null || { warn "git not found — needed to fetch SbarLua"; exit 1; }

say "building C helpers"
make -C helpers/menus >/dev/null
make -C helpers/audio_devices >/dev/null
make -C helpers/event_providers >/dev/null
make -C helpers/volume_keys >/dev/null
say "helpers built"

if [ ! -f "$HOME/.local/share/sketchybar_lua/sketchybar.so" ]; then
  say "installing SbarLua (lua bridge)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  git clone -q --depth 1 https://github.com/FelixKratz/SbarLua.git "$tmp"
  (cd "$tmp" && make install >/dev/null)
  rm -rf "$tmp"
  trap - EXIT
fi

if [ ! -f "$HOME/Library/Fonts/sketchybar-app-font.ttf" ]; then
  say "installing sketchybar-app-font"
  curl -sL "https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/sketchybar-app-font.ttf" \
    -o "$HOME/Library/Fonts/sketchybar-app-font.ttf" || warn "font install failed — space icons will be blank"
fi

# optional deps — widgets hide themselves when these are missing
say "checking optional deps (the audio probe takes a few seconds)"
command -v media-control >/dev/null || warn "media-control missing → media widget stays blank (brew install media-control)"
command -v cava >/dev/null || warn "cava missing → sonar EQ off"
if ! system_profiler SPAudioDataType 2>/dev/null | grep -q BlackHole; then
  warn "BlackHole missing → EQ would follow the microphone (brew install blackhole-2ch)"
fi
command -v herdr >/dev/null || warn "herdr missing → herd widget off"
command -v yabai >/dev/null || warn "yabai missing → spaces fall back to static 1..10"

say "done — run: sketchybar --reload (or start it however you run it)"

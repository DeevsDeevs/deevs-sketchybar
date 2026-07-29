#!/usr/bin/env bash

# deevs-sketchybar installer: builds C helpers, checks dependencies.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\033[1;32m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

command -v sketchybar >/dev/null || { warn "sketchybar not found — install it first (brew/nix)"; exit 1; }
command -v clang >/dev/null || { warn "clang not found — install Xcode command line tools"; exit 1; }

say "building C helpers"
make -C helpers/menus >/dev/null
make -C helpers/audio_devices >/dev/null
make -C helpers/event_providers >/dev/null
make -C helpers/volume_keys >/dev/null
make -C helpers/audiotap >/dev/null 2>&1 || warn "audiotap build failed → sonar falls back to cava/mic"
say "helpers built"

if [ ! -f "$HOME/.local/share/sketchybar_lua/sketchybar.so" ]; then
  say "installing SbarLua (lua bridge)"
  tmp="$(mktemp -d)"
  git clone -q --depth 1 https://github.com/FelixKratz/SbarLua.git "$tmp"
  (cd "$tmp" && make install >/dev/null)
  rm -rf "$tmp"
fi

if ! system_profiler SPFontsDataType 2>/dev/null | grep -q "sketchybar-app-font"; then
  say "installing sketchybar-app-font"
  curl -sL "https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/sketchybar-app-font.ttf" \
    -o "$HOME/Library/Fonts/sketchybar-app-font.ttf" || warn "font install failed — space icons will be blank"
fi

# optional deps — widgets hide themselves when these are missing
command -v media-control >/dev/null || warn "media-control missing → media widget off (brew install media-control)"
command -v cava >/dev/null || warn "cava missing → sonar off (also needs a loopback like BlackHole 2ch)"
command -v herdr >/dev/null || warn "herdr missing → herd widget off"
command -v yabai >/dev/null || warn "yabai missing → spaces fall back to static 1..10"

say "done — run: brew services restart sketchybar (or your service manager)"

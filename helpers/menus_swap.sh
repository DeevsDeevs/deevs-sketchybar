#!/usr/bin/env bash

# Spaces ↔ front-app menus swap.
#
# Runs the accessibility-backed `menus` helper and sets labels itself, because
# sketchybar must be the process that spawns it: when the lua config spawns it
# instead, macOS attributes the accessibility permission elsewhere and the
# helper returns nothing. State lives in a file so the toggle is idempotent
# across reloads.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
MENUS="$DIR/menus/bin/menus"
STATE="${TMPDIR:-/tmp}/sketchybar-menu-mode"
MAX="${MENU_SLOTS:-12}"

hide_menus() {
  local args=() i
  for ((i = 1; i <= MAX; i++)); do args+=(--set "menu.$i" drawing=off); done
  args+=(--set '/space\..*/' drawing=on)
  sketchybar "${args[@]}" >/dev/null 2>&1
  rm -f "$STATE"
}

show_menus() {
  local names=() line args=() i=1 first=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$first" = 1 ]; then first=0; continue; fi   # app menu = front_app label
    names+=("$line")
    [ ${#names[@]} -ge $MAX ] && break
  done < <("$MENUS" -l 2>/dev/null)

  if [ ${#names[@]} -eq 0 ]; then
    hide_menus
    return 0
  fi

  args=(--set '/space\..*/' drawing=off)
  for line in "${names[@]}"; do
    args+=(--set "menu.$i" label="$line" drawing=on)
    i=$((i + 1))
  done
  for ((; i <= MAX; i++)); do args+=(--set "menu.$i" drawing=off); done
  sketchybar "${args[@]}" >/dev/null 2>&1
  : >"$STATE"
}

case "${1:-toggle}" in
  refresh) [ -f "$STATE" ] && show_menus ;;
  hide) hide_menus ;;
  *) if [ -f "$STATE" ]; then hide_menus; else show_menus; fi ;;
esac

#!/usr/bin/env bash

set -u

readonly HOME_DIR="${HOME:-/Users/deevs}"
readonly CONFIG_DIR="${CONFIG_DIR:-$HOME_DIR/.config/sketchybar}"
readonly AUDIO_DEVICES_BIN="$CONFIG_DIR/helpers/audio_devices/bin/audio_devices"
readonly BRACKET="widgets.volume"
readonly POPUP_WIDTH=250
readonly LABEL_GREY="${LABEL_OFF:-0xff7f8490}"
readonly LABEL_WHITE="${LABEL_ON:-0xffe2e2e3}"

remove_items() {
  sketchybar --remove '/volume.device\..*/' >/dev/null 2>&1 || true
}

show_message() {
  local message="$1"
  sketchybar \
    --set "$BRACKET" popup.drawing=on \
    --add item volume.device.message "popup.$BRACKET" \
    --set volume.device.message width="$POPUP_WIDTH" align=center \
      label="$message" label.color="$LABEL_GREY"
}

popup_is_open() {
  sketchybar --query "$BRACKET" 2>/dev/null \
    | sed -n '/"popup"/,$p' | grep -m1 '"drawing"' | grep -q '"on"'
}

# Toggle against the live state, not a remembered one: picking a device closes
# the popup straight through the CLI, so any cached flag would go stale.
if popup_is_open; then
  remove_items
  sketchybar --set "$BRACKET" popup.drawing=off
  exit 0
fi

remove_items

if [[ ! -x "$AUDIO_DEVICES_BIN" ]]; then
  show_message "Audio device helper unavailable"
  exit 0
fi

sketchybar --set "$BRACKET" popup.drawing=on

index=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  IFS=$'\t' read -r current device_id device_name <<<"$line"
  [[ -z "${device_id:-}" || -z "${device_name:-}" ]] && continue

  item="volume.device.$index"
  label_color="$LABEL_GREY"
  if [[ "$current" == "1" ]]; then
    label_color="$LABEL_WHITE"
  fi

  click_script="$AUDIO_DEVICES_BIN set $device_id ${ROUTE_FLAG:-} && sketchybar --set /volume.device\\..*/ label.color=$LABEL_GREY --set \$NAME label.color=$LABEL_WHITE --set $BRACKET popup.drawing=off; sketchybar --trigger system_woke"

  sketchybar \
    --add item "$item" "popup.$BRACKET" \
    --set "$item" width="$POPUP_WIDTH" align=center \
      label="$device_name" label.color="$label_color" \
      click_script="$click_script"

  index=$((index + 1))
done < <("$AUDIO_DEVICES_BIN" list)

if [[ $index -eq 0 ]]; then
  show_message "No output devices found"
fi

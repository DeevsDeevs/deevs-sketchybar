#!/usr/bin/env bash

# Artwork goes to lua as a file path: base64 over the Mach bridge deadlocks it.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

readonly ART_DIR="${TMPDIR:-$HOME/.cache}"
readonly ART="${ART_DIR%/}/sketchybar_album_art.jpg"

# Let the lua config finish registering subscriptions before the first trigger.
sleep 5

media-control stream 2>/dev/null | while IFS= read -r line; do
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  payload="$(jq -c 'select(.type == "data") | .payload // {}' <<<"$line" 2>/dev/null)" || continue
  [[ -z "$payload" ]] && continue

  art="$(jq -r '.artworkData // empty' <<<"$payload")"
  if [[ -n "$art" ]]; then
    printf '%s' "$art" | base64 -d >"$ART.tmp" 2>/dev/null && sips -Z 128 "$ART.tmp" >/dev/null 2>&1 && mv -f "$ART.tmp" "$ART"
  fi

  if [[ "$(jq -r '.diff // false' <<<"$line")" == "true" ]]; then
    state="$(jq -c --argjson patch "$payload" '(. * $patch) | del(.artworkData)' <<<"${state:-{\}}")"
  else
    state="$(jq -c 'del(.artworkData)' <<<"$payload")"
  fi

  IFS=$'\t' read -r playing title artist app <<<"$(
    jq -r '[(.playing // false), (.title // ""), (.artist // ""), (.bundleIdentifier // "")] | @tsv' <<<"$state"
  )"

  track="$title	$artist	$app"
  sig="$playing	$track"

  [[ -n "$art" ]] && art_owner="$track"

  if [[ "$sig" != "${last_sig:-}" || -n "$art" ]]; then
    last_sig="$sig"
    sketchybar --trigger media_update \
      PLAYING="$playing" TITLE="$title" ARTIST="$artist" APP="$app" \
      ART_PATH="$([[ "${art_owner:-}" == "$track" ]] && printf '%s' "$ART")" \
      ART_NEW="$([[ -n "$art" ]] && printf 1 || printf 0)"
  fi
done

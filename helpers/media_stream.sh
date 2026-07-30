#!/usr/bin/env bash

# Streams now-playing changes into the custom sketchybar event "media_update".
# Artwork goes to lua as a file path: base64 over the Mach bridge deadlocks it.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

# TMPDIR is per-user (0700) on macOS — no world-writable /tmp symlink games.
readonly ART_DIR="${TMPDIR:-$HOME/.cache}"
readonly ART="${ART_DIR%/}/sketchybar_album_art.jpg"

# Let the lua config finish registering subscriptions before the first trigger.
sleep 5

media-control stream 2>/dev/null | while IFS= read -r line; do
  # Die with the bar, or this loop stays orphaned holding a MediaRemote subscription.
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  payload="$(jq -c 'select(.type == "data") | .payload // {}' <<<"$line" 2>/dev/null)" || continue
  [[ -z "$payload" ]] && continue

  art="$(jq -r '.artworkData // empty' <<<"$payload")"
  if [[ -n "$art" ]]; then
    printf '%s' "$art" | base64 -d >"$ART.tmp" 2>/dev/null && sips -Z 128 "$ART.tmp" >/dev/null 2>&1 && mv -f "$ART.tmp" "$ART"
  fi

  # Keep artworkData out of $state: every jq read below re-parses it otherwise.
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

  # Remember which track owns the on-disk art: a track without artwork must not
  # inherit the previous image (TMPDIR survives reboots).
  [[ -n "$art" ]] && art_owner="$track"

  if [[ "$sig" != "${last_sig:-}" || -n "$art" ]]; then
    last_sig="$sig"
    sketchybar --trigger media_update \
      PLAYING="$playing" TITLE="$title" ARTIST="$artist" APP="$app" \
      ART_PATH="$([[ "${art_owner:-}" == "$track" ]] && printf '%s' "$ART")" \
      ART_NEW="$([[ -n "$art" ]] && printf 1 || printf 0)"
  fi
done

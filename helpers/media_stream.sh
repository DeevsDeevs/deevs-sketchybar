#!/usr/bin/env bash

# Streams now-playing changes into the custom sketchybar event "media_update".
# Replaces the old 2s `media-control get` polling through sbar.exec, which
# pushed ~300KB of base64 artwork through the lua<->sketchybar Mach bridge on
# every tick and was implicated in deadlocks. Artwork is decoded here and
# passed to lua as a file path only.

set -u
export PATH="/usr/bin:/bin:/opt/homebrew/bin:$PATH"

# TMPDIR is per-user (0700) on macOS — no world-writable /tmp symlink games.
readonly ART_DIR="${TMPDIR:-$HOME/.cache}"
readonly ART="${ART_DIR%/}/sketchybar_album_art.jpg"

# The initial full-state line arrives instantly; wait for sketchybar to finish
# loading the lua config and registering subscriptions before the first trigger.
sleep 5

media-control stream 2>/dev/null | while IFS= read -r line; do
  # Without this the bar's death leaves this loop and its media-control
  # subscriber orphaned on launchd, holding a live MediaRemote subscription.
  pgrep -x sketchybar >/dev/null 2>&1 || exit 0

  payload="$(jq -c 'select(.type == "data") | .payload // {}' <<<"$line" 2>/dev/null)" || continue
  [[ -z "$payload" ]] && continue

  art="$(jq -r '.artworkData // empty' <<<"$payload")"
  if [[ -n "$art" ]]; then
    printf '%s' "$art" | base64 -d >"$ART.tmp" 2>/dev/null && sips -Z 128 "$ART.tmp" >/dev/null 2>&1 && mv -f "$ART.tmp" "$ART"
  fi

  # Strip artworkData before merging. Carried in $state it makes every read
  # below re-parse a few hundred KB of base64 per stream line — the very payload
  # cost this helper exists to keep off the bridge.
  if [[ "$(jq -r '.diff // false' <<<"$line")" == "true" ]]; then
    state="$(jq -c --argjson patch "$payload" '(. * $patch) | del(.artworkData)' <<<"${state:-{\}}")"
  else
    state="$(jq -c 'del(.artworkData)' <<<"$payload")"
  fi

  # One jq pass for the whole record rather than six herestrings.
  IFS=$'\t' read -r playing title artist app <<<"$(
    jq -r '[(.playing // false), (.title // ""), (.artist // ""), (.bundleIdentifier // "")] | @tsv' <<<"$state"
  )"

  sig="$playing	$title	$artist	$app"
  if [[ "$sig" != "${last_sig:-}" || -n "$art" ]]; then
    last_sig="$sig"
    sketchybar --trigger media_update \
      PLAYING="$playing" TITLE="$title" ARTIST="$artist" APP="$app" \
      ART_PATH="$ART" \
      ART_NEW="$([[ -n "$art" ]] && printf 1 || printf 0)"
  fi
done

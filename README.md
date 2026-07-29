# deevs-sketchybar

The layer above everything — a living, fully configurable [SketchyBar](https://github.com/FelixKratz/SketchyBar) setup — glass bar, real-nature wallpapers, and widgets that know what you're doing.

> Prototyped interactively before a single line of lua was written — the whole bar was designed in a clickable playground first.

## Install

```sh
git clone https://github.com/DeevsDeevs/deevs-sketchybar ~/.config/sketchybar
~/.config/sketchybar/install.sh     # builds helpers, installs SbarLua + app font
brew services restart sketchybar    # or your service manager
```

## Configure

Everything lives in [`config.lua`](config.lua) — **every widget is optional** and hides itself when its dependency is missing.

| key | what | values |
|---|---|---|
| `structure` | bar shape | `glass` · `islands` · `deck` · `mono` |
| `palette` | color world | 16 themes in [`palettes/`](palettes/) |
| `glass` | bar translucency | `0.0`–`1.0` |
| `media` | now playing | `cover`, `sonar` (cava), whitelist |
| `herd` | agent fleet | `hosts` incl. SSH targets |
| `session` | pomodoro | Session.app alias + deep links |
| `mood` | per-space accents | `true` / `false` |

Default ships as: `glass · everforest · glass 0.66 · sonar+session+herd`.

## What lives up here

- **Sonar** — the bar hears your music: live cava spectrum in the media widget
- **Herd** — mission control for AI agent fleets across local + SSH hosts (herdr integration): working counts, blocked-agent alerts, click-to-focus
- **Session** — pomodoro chip with live countdown, progress underline and focus stats, wired into Session.app's deep links and database
- **System cluster** — load-colored CPU sparkline, RAM, network in one bracket; per-core popup
- **Mood ring** — every workspace has its own accent; the bar breathes with you
- **Menus ↔ spaces swap** — focused app's real menus, in-bar, one click away
- **Per-space app icons**, media controls, volume device picker, calendar, battery — all popup-driven, zero hint text

## Dependencies

Two worlds, on purpose:

| dep | channel | why |
|---|---|---|
| sketchybar, yabai, lua, jq, **cava** | devbox/nix | reproducible, synced to dotfiles |
| [media-control](https://github.com/ungive/media-control) | brew | not packaged in nixpkgs |
| [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) | brew cask | audio *driver*; routing is automated by `audio_devices` |

### Sonar audio routing (automatic)

The EQ needs to hear what you hear. Install the loopback once:

```sh
brew install blackhole-2ch
sudo killall coreaudiod     # load the driver without rebooting
```

Then set `audio.auto_route = true` in `config.lua`. Picking an output in the
bar's volume popup builds a multi-output aggregate of *that device +
BlackHole* and selects it: sound plays from the device you chose, cava reads
the identical signal from BlackHole. Switch to AirPods, a monitor, speakers —
click it in the bar and the sonar follows. Audio MIDI Setup is never involved,
and BlackHole is hidden from the device list.

**The trade-off:** macOS gives aggregate devices no hardware volume, so while
routing is on the F-row volume keys do nothing — that is a platform
limitation, not something a config can fix. The bar's volume chip still works
(scroll it, or drag the slider in its popup), because `audio_devices volume`
targets the real device underneath the aggregate. Routing is therefore
**off by default**; turn it on only if you want the EQ more than the keys.

`audio_devices unroute` returns to a plain device immediately.

Without BlackHole the helper just sets the device directly and the EQ falls
back to the default input (i.e. the microphone).

#### Why not driverless?

Both Apple APIs for capturing system audio without a loopback were built and
tested here, and neither delivers on macOS 15:

- **CoreAudio process taps** (14.4+) — tap and aggregate device are created
  successfully, but the IO proc only ever receives silence.
- **ScreenCaptureKit** `capturesAudio` — the stream starts and *video* frames
  arrive (proving Screen Recording is granted), yet audio sample buffers never
  fire. Identical whether launched from a terminal, via `open`, or spawned by
  sketchybar, so it isn't a TCC-parent problem.

## Window manager fit

The floating structures need the WM to reserve space:

| structure | yabai setting |
|---|---|
| `glass` / `mono` | `yabai -m config external_bar all:52:0` |
| `islands` | `yabai -m config external_bar all:54:0` |
| `deck` | `yabai -m config external_bar all:0:58` |

## Troubleshooting

**Menus swap does nothing / menus are blank.** The `menus` helper needs
Accessibility, and macOS grants it to the *spawning* process — which must be
sketchybar itself (that's why the swap runs as a shell script, not from lua).
Grant it under System Settings → Privacy & Security → Accessibility, pick the
real binary (`~/.local/share/devbox/.../bin/sketchybar` for devbox/nix installs),
then **fully restart** sketchybar — a `--reload` keeps the old permission state.
Package updates change the binary and silently invalidate the grant.

**Sonar flat / reacting to the room.** `audiotap` needs the "System Audio
Recording" permission (prompted on first run). Without it, sonar falls back to
cava on the default input, which is the microphone.

**Nothing reacts to clicks.** Check the bar isn't covered: `yabai -m config
external_bar` must reserve at least the bar height plus its `y_offset`.

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and [SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz.
Managed via [chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

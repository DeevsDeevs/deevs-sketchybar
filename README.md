# deevs-sketchybar

The layer above everything — a living, fully configurable [SketchyBar](https://github.com/FelixKratz/SketchyBar) setup — glass bar, real-nature wallpapers, and widgets that know what you're doing.

> Prototyped interactively before a single line of lua was written — the whole bar was designed in a clickable playground first.

## Install

```sh
git clone https://github.com/DeevsDeevs/deevs-sketchybar ~/.config/sketchybar
~/.config/sketchybar/install.sh     # builds helpers, installs SbarLua + app font
sketchybar --reload                 # or start it however you run it
```

`--reload` re-execs the config and is all you need after editing `config.lua`.
The one exception is anything touching Accessibility (the menus swap): macOS
pins that grant to the running process, so it needs a real restart.

## Configure

Everything lives in [`config.lua`](config.lua) — **every widget is optional** and hides itself when its dependency is missing.

| key | what | values |
|---|---|---|
| `structure` | bar shape | `glass` · `islands` · `deck` · `mono` |
| `palette` | color world | 16 themes in [`palettes/`](palettes/) |
| `glass` | bar translucency | `0.0`–`1.0` |
| `media` | now playing | `cover`, `sonar`, `eq_bars`, `eq_height`, whitelist |
| `herd` | agent fleet | `hosts` incl. SSH targets |
| `session` | pomodoro | Session.app alias + deep links |
| `mood` | per-space accents | `true` / `false` |
| `audio.auto_route` | loopback routing for the EQ | `true` / `false` |
| `menus_swap` | click the app name for its menus | `true` / `false` |

Default ships as: `glass · everforest · glass 0.66 · sonar+session+herd`.

## What lives up here

- **Sonar** — the bar hears your music: live cava spectrum in the media widget
- **Herd** — mission control for AI agent fleets across local + SSH hosts (herdr integration): working counts, blocked-agent alerts, click-to-focus
- **Session** — pomodoro chip with a live countdown over the intent name and a ring that fills as the block burns down; controls and focus stats wired to Session.app's deep links and database
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

### What the sonar needs

The EQ bars are driven by cava, and cava can only listen to an *input*. To
make it hear your music rather than your room, audio is routed through a
loopback. Three things, once:

```sh
devbox global add cava        # or: brew install cava
brew install blackhole-2ch    # the loopback driver
sudo killall coreaudiod       # load the driver without rebooting
```

Then in `config.lua`:

```lua
media = { sonar = true },
audio = { auto_route = true },
```

From then on it is automatic. **Picking an output in the bar's volume popup**
builds a multi-output aggregate of *that device + BlackHole* and selects it:
sound plays from the device you picked, cava reads the identical signal from
BlackHole. Switch to AirPods, a monitor, speakers — click it in the bar and
the sonar follows. Audio MIDI Setup is never involved, and both BlackHole and
the aggregate stay hidden from the device list.

`audio_devices unroute` drops back to a plain device at any time, and
`audio_devices volume [level|+N|-N]` always targets the real device.

Skip BlackHole and everything still works — the helper just sets devices
directly and the EQ follows the default input (your microphone), which is
only useful on speakers.

#### Volume keys while routed

Aggregate devices expose no volume of their own, so AppleScript reports
`missing value` for them. macOS itself still drives the underlying device, so
the F-row keys and the system HUD keep working — no extra piece required.

If yours ever go dead while routed, set `audio.volume_keys = true`:
`helpers/volume_keys` then taps the three volume keys and applies them to the
real device beneath the aggregate, drawing the same system HUD through
`OSDUIHelper`. It is off by default because nothing should sit in your input
path unless it earns its place; it consumes only volume/mute, and every other
media key passes through untouched.

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

**Sonar flat.** Nothing is reaching cava. Check in order: `cava` is installed,
BlackHole shows up (`system_profiler SPAudioDataType | grep BlackHole`),
`audio.auto_route = true`, and you have picked your output **from the bar's
volume popup** at least once — that click is what builds the aggregate.

**Sonar follows the room instead of the music.** BlackHole is missing or the
output is not routed, so cava is on the microphone. Same checklist.

**Volume keys dead while routed.** Set `audio.volume_keys = true` (see above).

**Nothing reacts to clicks.** Check the bar isn't covered: `yabai -m config
external_bar` must reserve at least the bar height plus its `y_offset`.

## Layout

```
config.lua          what you edit — every widget optional
core/               entry point, shared context, fonts
palettes/           16 colour worlds, one file each
structures/         glass · islands · deck · mono (layout only)
widgets/            one self-contained module per feature
helpers/            C and shell helpers (built by install.sh)
```

Widgets never reference a structure and structures never reference a widget:
a structure only sets the bar shape and the shared item style, so any widget
works under any structure.

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and [SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz.
Managed via [chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

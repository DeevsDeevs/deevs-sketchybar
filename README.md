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
| [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) | brew cask | it's an audio *driver* — only ships as a signed installer |

### Sonar audio routing

The sonar visualizes whatever cava hears. Out of the box that's the default
input (microphone — reacts to your speakers ambiently). For a true
system-audio tap, BlackHole is the chosen loopback (free, open source, the
de-facto standard; Loopback/SoundSource are paid, Soundflower is abandoned):

```sh
brew install blackhole-2ch
```

Then **Audio MIDI Setup → + → Multi-Output Device** → check your speakers
*and* BlackHole 2ch → set it as sound output. Set BlackHole 2ch as the
*input* device (or leave `source = auto` in `helpers/sonar.sh` and make
BlackHole the default input). Nix's cava build defaults to pulseaudio;
`sonar.sh` already forces `portaudio`.

## Window manager fit

The floating structures need the WM to reserve space:

| structure | yabai setting |
|---|---|
| `glass` / `mono` | `yabai -m config external_bar all:52:0` |
| `islands` | `yabai -m config external_bar all:54:0` |
| `deck` | `yabai -m config external_bar all:0:58` |

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and [SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz.
Managed via [chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

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

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and [SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz.
Managed via [chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

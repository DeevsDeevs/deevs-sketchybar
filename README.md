# deevs-sketchybar

A configurable [SketchyBar](https://github.com/FelixKratz/SketchyBar) setup in Lua.
Translucent glass bar, live audio spectrum, pomodoro ring, AI agent fleet, per-workspace
accent colours. Every widget is optional and hides itself when its dependency is missing.

4 bar structures · 16 palettes · 18 widgets · MIT

## Install

```sh
git clone https://github.com/DeevsDeevs/deevs-sketchybar ~/.config/sketchybar
~/.config/sketchybar/install.sh   # helpers, SbarLua, the app font
sketchybar --reload
```

`--reload` is all you need after editing `config.lua`. Two things want a full restart
instead: the menus swap, and anything that re-grants Accessibility.

## Configure

Everything is in [`config.lua`](config.lua). Every widget takes a block or a bare
boolean — `media = false` and `media = { enabled = false }` are the same.

| key | what | values |
|---|---|---|
| `structure` | bar shape | `glass` · `islands` · `deck` · `mono` |
| `palette` | colour world | one of 16 in [`palettes/`](palettes/) |
| `glass` | translucency | `0.0`–`1.0` (`islands` clamps to ≥ 0.8, `mono` ignores) |
| `chips` | rounded slab behind each group | `true` · `false` for a flat row |
| `bar` | `height`, `icon` | `icon` is the leftmost glyph |
| `mood` | per-workspace accent colours | `true` · `false` |

Ships as `glass` · `everforest` · `0.66`, with sonar, session and herdr on.

## Widgets

Always on: the brand glyph and the front-app name.

| key | what | keys |
|---|---|---|
| `spaces` | per-space chips with app icons | `icons`, `max` |
| `media` | now playing, album art, spectrum EQ | `cover`, `sonar`, `side`, `text_width`, `eq_bars`, `whitelist` |
| `system` | CPU sparkline · RAM · network | `host`, `poll` |
| `session` | pomodoro ring and countdown | needs Session.app |
| `herdr` | AI agent fleet, local and over SSH | `host`, `hosts`, `poll`, `watch` |
| `repo` | repo · branch · dirty count · CI dot | `path`, `ci` (needs `gh`) |
| `servers` | reachability dots, or a host picker | `select`, `default`, `filter`, `hosts` |
| `weather` | glyph and temperature | `place` |
| `surf` | wave height and period for one break | `lat`, `lon`, `up` |
| `caffeine` | hold the Mac awake, timed or not | `durations` |
| `calendar` `battery` `volume` `vpn` `mic` `lang` | small status chips | — |
| `menus_swap` | click the app name to swap spaces for menus | `true` · `false` |
| `audio` | loopback routing for the EQ | `auto_route`, `volume_keys` |

## Targeting a host

With `servers.select = true` the servers chip becomes a picker, and any widget set to
`host = "selected"` follows it. Pick `prod-1` and the system cluster shows that
machine's load while herdr lists its agents.

```lua
servers = { enabled = true, select = true, default = "local" },
system  = { host = "selected" },
herdr   = { host = "selected" },
```

`host` takes `"local"` (or absent), `"selected"`, or an ssh alias. Hosts come from
`~/.ssh/config` — `Include`, `Match` and `Port` are honoured, `ProxyJump`-only hosts are
skipped. Clicking an agent jumps to it, locally or over ssh.

## Sonar

The EQ is driven by cava, and cava can only listen to an *input* — so output is routed
through a loopback. Three things, once:

```sh
devbox global add cava        # or: brew install cava
brew install blackhole-2ch    # the loopback driver
sudo killall coreaudiod       # load it without rebooting
```

Then `media = { sonar = true }` and `audio = { auto_route = true }`.

After that it is automatic: **picking an output in the bar's volume popup** builds a
multi-output aggregate of that device + BlackHole and selects it. Sound plays from the
device you picked, cava reads the same signal. Audio MIDI Setup is never involved.

`audio.volume_keys` is required rather than optional while routed — an aggregate exposes
no volume of its own, so the F-row keys would otherwise do nothing. Both ship on together.

Skip BlackHole and everything still works; the EQ just follows your microphone.

## Requirements

| dep | from | why |
|---|---|---|
| sketchybar, yabai, lua, jq, cava | devbox/nix | reproducible, synced to dotfiles |
| [media-control](https://github.com/ungive/media-control) | brew | not in nixpkgs |
| [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) | brew cask | an audio *driver*; routing itself is automated |

Floating structures need the window manager to reserve space:

| structure | reserve | yabai |
|---|---|---|
| `glass` · `islands` | `height + 12` (52) | `yabai -m config external_bar all:52:0` |
| `mono` | `height + 6` (46) | `yabai -m config external_bar all:46:0` |
| `deck` | `height + 18` (58), bottom | `yabai -m config external_bar all:0:58` |

## Troubleshooting

**Menus swap does nothing.** The `menus` helper needs Accessibility, granted to the
*spawning* process — sketchybar itself. Point the grant at the real binary, then fully
restart. Package updates change the binary and silently invalidate it.

**No EQ bars.** They are only created if the config can see `cava` on its own PATH. A
launchd-started sketchybar inherits a bare PATH, so it working in your shell proves
nothing.

**EQ flat, or following the room.** cava is on your microphone. Check BlackHole is
installed, `audio.auto_route = true`, and that you have picked an output from the volume
popup at least once — that click is what builds the aggregate.

**Weather or surf stuck on `--`.** They need Location Services. Rebuilding the helper
revokes the grant. Naming `weather.place` skips location entirely.

**Nothing reacts to clicks.** The bar is covered — `external_bar` must reserve at least
the bar height plus its offset.

## Layout

```
config.lua     what you edit
core/          entry point, shared context, fonts
palettes/      16 colour worlds, one file each
structures/    glass · islands · deck · mono — bar shape only
widgets/       one self-contained module per feature
helpers/       C and shell helpers, built by install.sh
```

Widgets never reference a structure and structures never reference a widget, so any
widget works under any structure.

[`docs/internals.md`](docs/internals.md) covers the parts that are not obvious from the
code: how popups behave across displays, how an agent click finds its terminal tab, why
the EQ needs a loopback at all.

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and
[SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz. Managed with
[chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/)
from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

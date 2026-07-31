# deevs-sketchybar

A configurable [SketchyBar](https://github.com/FelixKratz/SketchyBar) setup in
Lua: a translucent glass bar with a live audio spectrum, a pomodoro ring, agent
fleet status, and per-workspace accent colours. Every widget is optional.

## Install

```sh
git clone https://github.com/DeevsDeevs/deevs-sketchybar ~/.config/sketchybar
~/.config/sketchybar/install.sh   # helpers, SbarLua, the app font
sketchybar --reload
```

`--reload` re-execs the config and is all you need after editing `config.lua`.
sketchybar runs as a plain process, not a brew service — to restart it fully,
`killall sketchybar` and launch it again however you start it.

One thing needs that full restart rather than a reload: the menus swap. macOS
pins an Accessibility grant to the running process, so a reload keeps the old
permission state.

## Configure

Everything lives in [`config.lua`](config.lua). Every widget takes either a
block or a bare boolean — `media = false` and `media = { enabled = false }` are
the same thing — and each one hides itself when its dependency is missing
rather than sitting there empty.

### Look

| key | what | values |
|---|---|---|
| `structure` | bar shape | `glass` · `islands` · `deck` · `mono` |
| `palette` | colour world | one of 16 in [`palettes/`](palettes/) |
| `glass` | translucency | `0.0`–`1.0` (`islands` clamps to ≥ 0.8, `mono` ignores it) |
| `chips` | rounded slab behind each widget group | `true` · `false` for a flat row |
| `bar` | `height`, `icon` | `icon` is the leftmost glyph |
| `mood` | per-workspace accent colours | `true` · `false` |

### Widgets

Always on: the brand glyph and the front-app name. Everything else is optional.

| key | what | keys |
|---|---|---|
| `spaces` | per-space chips with app icons | `icons`, `max` |
| `media` | now playing, album art, spectrum EQ | `cover`, `sonar`, `text_width`, `eq_bars`, `eq_height`, `whitelist` |
| `system` | CPU sparkline · RAM · network | `host`, `poll` |
| `session` | pomodoro ring and countdown | needs Session.app |
| `herdr` | AI agent fleet, local and over SSH | `host`, `hosts`, `poll` |
| `repo` | repo · branch · dirty count · CI dot | `path` to pin, `ci` (needs `gh`) |
| `servers` | reachability dots, or a host selector | `select`, `default`, `filter`, `hosts` |
| `weather` | glyph and temperature | `place` |
| `surf` | wave height and period for one break | `lat`, `lon`, `up` |
| `calendar` `battery` `volume` `vpn` `mic` `lang` | small status chips | — |
| `menus_swap` | click the app name to swap spaces for its menus | `true` · `false` |
| `audio` | loopback routing for the EQ | `auto_route`, `volume_keys` |

### Targeting a host

With `servers.select = true` the servers chip stops showing a dot per host and
becomes a picker: it names one target, and any widget set to `host = "selected"`
follows it. Pick `prod-1` and the perf cluster shows that machine's load while
herdr lists its agents.

```lua
servers = { enabled = true, select = true, default = "local" },
system  = { host = "selected" },
herdr   = { host = "selected" },
```

`host` takes three answers and defaults to the first, so configs written before
this existed keep working untouched:

| value | meaning |
|---|---|
| absent or `"local"` | this machine, as always |
| `"selected"` | follows the servers picker |
| an ssh alias | that host, whether or not a picker exists |

Hosts come from `~/.ssh/config`, so the alias is the ssh target — nothing to
configure twice. The chip shows the shortest unambiguous tail of the alias
(`deevs.hetzner.berezka` and `deevs.aws.berezka` render as `hetzner.berezka` and
`aws.berezka`).

Clicking an agent jumps to it. A local one switches herdr to that pane, moves to
the space its terminal is on, and raises that terminal — the exact process, since
a terminal often runs several and activating the bundle picks the wrong one. A
remote one focuses the agent on its host and attaches a local tab to that session,
reusing the tab if one is already pointed there.

Remote herdr runs through `$SHELL -ic` rather than a bare `ssh host herdr …`.
Version managers (devbox, nix, mise, asdf) put the binary on `PATH` from the
interactive rc, which plain ssh never sources — without this the host reports
"no agents" while agents are running on it. Your rc must not print to stdout.

Remote perf is **polled, not pushed**. Local CPU and network come from C event
providers that fire every 2s; nothing on another machine can push into your bar,
so a remote target is one `ssh` per `poll` seconds reading `/proc`. The host needs
`/proc` (any Linux) and key-based ssh. When a poll fails the numbers blank to `···`
rather than holding the last value — an unreachable host and an idle one must not
read the same.

`weather` and `surf` use [Open-Meteo](https://open-meteo.com) — no key, no
account — and locate you through CoreLocation, so no coordinates or city name
have to live in this file. Set `weather.place` to name a city instead, or
`surf.lat`/`surf.lon` to watch a break you are not standing on. The marine
model's grid is coarse enough that an inland fix snaps to the nearest water.

Location needs a grant. CoreLocation ignores a bare binary — authorization is
per app bundle — so `install.sh` builds `helpers/location` into a small signed
`.app`. macOS will ask once. Because the grant is keyed to the code signature
and `codesign --sign -` is ad-hoc, rebuilding the helper changes its identity
and revokes the grant, the same trap as Accessibility below.

`servers` reads `~/.ssh/config` rather than taking a host list, so no addresses
end up in this file. Every non-wildcard `Host` becomes a dot, each resolved with
`ssh -G` so `Include`, `Match` and `Port` are honoured; `filter` narrows that set
by Lua pattern and `hosts = { "alias", … }` replaces discovery outright. Hosts
behind a `ProxyJump` are skipped, because their resolved address is only
reachable from the jump host and a direct probe would sit there permanently red.

`repo` follows whichever repo your shell is in, which needs the shell to say so —
nothing outside it can tell, since one terminal process owns every window and
tab. Add to `.zshrc`:

```sh
_sbar_repo_cwd() { sketchybar --trigger repo_cwd RPATH="$PWD" > /dev/null 2>&1 &! }
add-zsh-hook chpwd _sbar_repo_cwd
add-zsh-hook precmd _sbar_repo_cwd
```

Setting `path` pins the chip to one repo instead and ignores the hook. Outside a
repo the chip keeps the last one and dims, rather than reflowing the bar on every
`cd` to `~`.

Click it for the full branch, upstream with ahead/behind, staged · unstaged ·
untracked counts, the last commit and the CI verdict in words. Those rows act:
repo, branch and changes open the checkout in `$EDITOR`, last and upstream run
`gh browse`, and ci opens the run.

The dot beside it is CI for the current branch — green `success`, amber running,
red `failure` or `timed_out`, dim for `skipped`/`cancelled`/`neutral` (which say
nothing about the code), and absent when there is no run, no GitHub remote or no
`gh`. The `servers` dots read the same way: green reachable, red not, dim not yet
probed. A private repo opens as a GitHub *404* rather than a permission error if
the browser is not signed in to an account with access — that is GitHub, not a
bad link.

Ships as `glass` · `everforest` · translucency `0.66`, with sonar, session and
herdr on.

## Sonar

The EQ bars are driven by cava, and cava can only listen to an *input*. To make
it hear your music instead of your room, output is routed through a loopback.
Three things, once:

```sh
devbox global add cava        # or: brew install cava
brew install blackhole-2ch    # the loopback driver
sudo killall coreaudiod       # load it without rebooting
```

Then set `media = { sonar = true }` and `audio = { auto_route = true }`.

From there it is automatic. **Picking an output in the bar's volume popup** is
what builds a multi-output aggregate of *that device + BlackHole* and selects
it: sound plays from the device you picked, cava reads the identical signal from
BlackHole. Switch to AirPods, a monitor, speakers — click it in the bar and the
sonar follows. Audio MIDI Setup is never involved, and both BlackHole and the
aggregate stay hidden from the device list.

`audio_devices unroute` drops back to a plain device, and `audio_devices volume
[level|+N|-N]` always targets the real device underneath.

Skip BlackHole and everything still works — the helper sets devices directly and
the EQ follows the default *input*, i.e. your microphone, which is only
interesting on speakers.

### Volume keys while routed

Aggregate devices expose no volume of their own — AppleScript reports `missing
value` for one — and macOS does **not** quietly fall through to the device
underneath. While `auto_route` is on, the F-row volume keys and the system HUD
do nothing by themselves, so `audio.volume_keys = true` is required rather than
optional. Both ship on together for that reason.

`helpers/volume_keys` taps the three volume keys, applies them to the real
device beneath the aggregate, and draws the ordinary system HUD through
`OSDUIHelper`. It consumes only volume and mute — brightness, playback, mission
control and keyboard backlight pass through untouched — and it stands down
whenever the aggregate is not the default output.

Turn `auto_route` off and you can turn this off with it: on a plain device macOS
handles the keys itself, and you lose only the EQ.

### Why not driverless?

Both Apple APIs for capturing system audio without a loopback were built and
tested here, and neither works on macOS 15:

- **CoreAudio process taps** (14.4+) — tap and aggregate device are created
  successfully, but the IO proc only ever receives silence.
- **ScreenCaptureKit** `capturesAudio` — the stream starts and *video* frames
  arrive, proving Screen Recording is granted, yet audio sample buffers never
  fire. Identical whether launched from a terminal, via `open`, or spawned by
  sketchybar, so it isn't a TCC-parent problem.

## Dependencies

Two channels, on purpose:

| dep | from | why |
|---|---|---|
| sketchybar, yabai, lua, jq, cava | devbox/nix | reproducible, synced to dotfiles |
| [media-control](https://github.com/ungive/media-control) | brew | not in nixpkgs |
| [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) | brew cask | an audio *driver*; the routing itself is automated |

## Window manager fit

The floating structures need the WM to reserve space. Each figure below is
`bar.height` plus the structure's own offset plus a few px so windows don't butt
against the bar; the numbers in parentheses are for the default height of 40.

| structure | reserve | yabai |
|---|---|---|
| `glass` | `height + 12` (52) | `yabai -m config external_bar all:52:0` |
| `islands` | `height + 12` (52) | `yabai -m config external_bar all:52:0` |
| `mono` | `height + 6` (46) | `yabai -m config external_bar all:46:0` |
| `deck` | `height + 18` (58), bottom | `yabai -m config external_bar all:0:58` |

## Troubleshooting

**Menus swap does nothing, or menus are blank.** The `menus` helper needs
Accessibility, and macOS grants it to the *spawning* process — which has to be
sketchybar itself. That is why the swap runs as a shell script rather than from
Lua. Grant it under System Settings → Privacy & Security → Accessibility,
pointing at the real binary (`~/.local/share/devbox/.../bin/sketchybar` for a
devbox/nix install), then fully restart sketchybar. Package updates change the
binary and silently invalidate the grant.

**No EQ bars at all.** They are only created if the config can see `cava` on its
own PATH. A launchd-started sketchybar inherits a bare PATH, so `install.sh`
working in your shell proves nothing. Check `cava` resolves for sketchybar
itself.

**EQ bars present but flat, or following the room instead of the music.** cava
is on your microphone. Confirm BlackHole is installed (`system_profiler
SPAudioDataType | grep BlackHole`), `audio.auto_route = true`, and that you have
picked your output **from the bar's volume popup** at least once — that click is
what builds the aggregate.

**Volume keys dead while routed.** Set `audio.volume_keys = true`.

**Weather or surf stuck on `--`.** They need Location Services. Check the grant
for `sketchybar-location` under System Settings → Privacy & Security → Location
Services, and remember that rebuilding the helper revokes it. Naming
`weather.place` skips location entirely.

**Nothing reacts to clicks.** The bar is covered. `yabai -m config external_bar`
must reserve at least the bar height plus its offset — see the table above.

## Layout

```
config.lua     what you edit
core/          entry point, shared context, fonts
palettes/      16 colour worlds, one file each
structures/    glass · islands · deck · mono — bar shape only
widgets/       one self-contained module per feature
helpers/       C and shell helpers, built by install.sh
```

Widgets never reference a structure and structures never reference a widget: a
structure sets the bar shape and the shared item style, nothing more, so any
widget works under any structure.

## Credits

Built on [SketchyBar](https://github.com/FelixKratz/SketchyBar) and
[SbarLua](https://github.com/FelixKratz/SbarLua) by Felix Kratz. Managed with
[chezmoi externals](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/)
from [my dotfiles](https://github.com/DeevsDeevs/dotfiles).

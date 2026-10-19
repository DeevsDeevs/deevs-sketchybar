# Internals

The parts of this config that are not obvious from reading it — behaviour of
sketchybar and macOS that took a while to pin down, and the reasons some things are
built the way they are.

## Popups across two displays

Space chips sort themselves out on their own: sketchybar resolves each one to the
display owning that mission control index, so every display shows its own. `spaces.max`
only has to be at least as high as your highest index, since indices are global and a
second display's spaces sit at the end.

Popups cannot be on both bars at once. An item gets **one** popup window with a single
anchor, and every bar rewrites that anchor while the popup is open — so with two bars
the dropdown opens on whichever redrew last, positioned in that bar's coordinates.
Nothing in the click path records which bar was clicked, so it cannot simply follow the
mouse.

Widgets that own a popup are therefore set to `display = active` and live on the display
you are working on, moving with you. Opening one always works, because exactly one bar
is laying it out. The whole widget travels, popup rows included: moving only the item
that holds the popup leaves a chip with a hole in it, and leaving the rows behind opens
an empty popup. Widgets without a popup — clock, weather, system, spaces — stay on every
display, and a shared chip simply gets shorter on the display you are not using.

A widget declares this with `ctx.owns_popup()` on its first line. That is all it needs;
every item it adds afterwards, whenever it adds them, follows automatically.

## Clicking an agent

A local agent switches herdr to that pane, moves to the space its terminal is on, and
raises that terminal — the exact process, since a terminal often runs several and
activating the bundle picks the wrong one.

A remote one lives in the same local herdr window, as a saved machine. The click
focuses the agent on its server with `herdr --machine <id> agent focus` and raises the
window; herdr has no API to select a machine in a running client, so picking it in the
sidebar is the last step.

When herdr shares a terminal window with other tabs, raising the window would land on
whichever tab was last on top, so the click finds herdr's tab first. herdr publishes no
title of its own and its tty is absent from the accessibility tree, but a title written
to that tty *does* reach the tab — so the click stamps a marker there, reads the tabs
back to see which one changed, and puts the old title straight back. It survives tabs
being reordered or closed. `herdr.tab` pins an index instead, for terminals with no tab
group to read.

Rows are named by their tab's own label rather than the pane id, taken from
`herdr api snapshot`, which carries tabs alongside agents in a single call — over ssh
the round trip is the whole cost. Tabs nobody renamed are numbered by herdr, and "3"
tells you less than the pane does, so those fall back to it.

## Remote hosts

Remote agents come from herdr's saved machines (`herdr machine list --json`), each read
with `herdr --machine <id> api snapshot` every `herdr.remote_poll` seconds. herdr owns
the ssh connection and finds its remote binary on its own; a devbox or nix install that
is only on the interactive `PATH` needs a `~/.local/bin/herdr` link. The list is re-read
on every sweep, so `machine add`/`disable` shows up without a reload, and a machine that
stops answering is listed as unreachable rather than idle.

Remote perf is **polled, not pushed**. Local CPU and network come from C event providers
that fire every 2s; nothing on another machine can push into your bar, so a remote
target is one `ssh` per `poll` seconds reading `/proc`. The host needs `/proc` (any
Linux) and key-based ssh. When a poll fails the numbers blank to `···` rather than
holding the last value — an unreachable host and an idle one must not read the same.

## Location

`weather` and `surf` use [Open-Meteo](https://open-meteo.com) — no key, no account — and
locate you through CoreLocation, so no coordinates or city name have to live in
`config.lua`. Set `weather.place` to name a city instead, or `surf.lat`/`surf.lon` to
watch a break you are not standing on. The marine model's grid is coarse enough that an
inland fix snaps to the nearest water.

CoreLocation ignores a bare binary — authorization is per app bundle — so `install.sh`
builds `helpers/location` into a small signed `.app`. macOS asks once. The grant is keyed
to the code signature and `codesign --sign -` is ad-hoc, so rebuilding the helper changes
its identity and revokes it, the same trap as Accessibility.

## The repo chip

`repo` follows whichever repo your shell is in, which needs the shell to say so —
nothing outside it can tell, since one terminal process owns every window and tab:

```sh
_sbar_repo_cwd() { sketchybar --trigger repo_cwd RPATH="$PWD" > /dev/null 2>&1 &! }
add-zsh-hook chpwd _sbar_repo_cwd
add-zsh-hook precmd _sbar_repo_cwd
```

Setting `path` pins the chip to one repo and ignores the hook. Outside a repo the chip
keeps the last one and dims, rather than reflowing the bar on every `cd` to `~`.

Click it for the full branch, upstream with ahead/behind, staged · unstaged · untracked
counts, the last commit and the CI verdict in words. Those rows act: repo, branch and
changes open the checkout in `$EDITOR`, last and upstream run `gh browse`, ci opens the
run.

The dot is CI for the current branch — green `success`, amber running, red `failure` or
`timed_out`, dim for `skipped`/`cancelled`/`neutral` (which say nothing about the code),
absent when there is no run, no GitHub remote or no `gh`. The `servers` dots read the
same way. A private repo opens as a GitHub *404* rather than a permission error if the
browser is not signed in to an account with access — that is GitHub, not a bad link.

## Volume while routed

Aggregate devices expose no volume of their own — AppleScript reports `missing value`
for one — and macOS does **not** quietly fall through to the device underneath. While
`auto_route` is on, the F-row volume keys and the system HUD do nothing by themselves,
which is why `audio.volume_keys` is required rather than optional.

`helpers/volume_keys` taps the three volume keys, applies them to the real device beneath
the aggregate, and draws the ordinary system HUD through `OSDUIHelper`. It consumes only
volume and mute — brightness, playback, mission control and keyboard backlight pass
through untouched — and stands down whenever the aggregate is not the default output.

A device exposes volume either as one master control or as one control per channel.
Taking the first that exists leaves every other channel untouched, which is how a headset
with no master ended up with its left channel at 0 and its right still playing. Every
element is driven.

## Why not driverless capture

Both Apple APIs for capturing system audio without a loopback were built and tested here,
and neither works on macOS 15:

- **CoreAudio process taps** (14.4+) — tap and aggregate device are created successfully,
  but the IO proc only ever receives silence.
- **ScreenCaptureKit** `capturesAudio` — the stream starts and *video* frames arrive,
  proving Screen Recording is granted, yet audio sample buffers never fire. Identical
  whether launched from a terminal, via `open`, or spawned by sketchybar, so it is not a
  TCC-parent problem.

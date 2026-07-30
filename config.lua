-- deevs-sketchybar user config.
-- Every widget is optional. Delete a block or set enabled = false and it is gone.
return {
    structure = "glass",     -- glass | islands | deck | mono
    palette   = "everforest",-- see palettes/
    glass     = 0.66,        -- bar translucency 0..1 (1 = opaque)
    chips     = true,        -- rounded slab behind every widget; false = flat row

    bar = {
        height = 40,
        icon = "󰌪",          -- leftmost glyph; "" for the classic
    },

    spaces = {
        enabled = true,
        icons = true,        -- per-space app icons
        max = 10,
    },

    menus_swap = true,       -- click front app name: spaces ↔ app menus

    media = {
        enabled = true,
        cover = true,        -- album art, with controls in its popup
        sonar = true,        -- spectrum EQ (needs cava; see audio.auto_route)
        text_width = 150,    -- px box for the hover text; long titles scroll inside it
        eq_bars = 12,
        eq_height = 16,      -- px at full scale
        whitelist = { ["com.spotify.client"] = true, ["com.apple.Music"] = true },
    },

    system = {
        enabled = true,      -- cpu sparkline + ram + net in one cluster
    },

    herdr = {
        enabled = true,      -- agent fleet (needs the herdr CLI)
        hosts = {
            { name = "local" },
            -- { name = "prod-1", ssh = "deevs@prod-1" },
        },
        poll = 5,            -- seconds
    },

    session = {
        enabled = true,      -- Session.app pomodoro (needs Session.app)
    },

    mood = true,             -- per-space accent colors

    volume   = { enabled = true },

    -- Sonar needs a copy of your audio, which means routing output through a
    -- multi-output aggregate (device + BlackHole). macOS gives aggregates no
    -- hardware volume, so the F-row volume keys stop working while it is on —
    -- the bar's own volume chip (click/scroll) keeps working either way.
    audio = {
        auto_route = true,   -- route through <device + BlackHole> so sonar hears music
        volume_keys = true,  -- required while auto_route is on: see the note above
    },
    battery  = { enabled = true },
    calendar = { enabled = true },

    -- small optional chips
    vpn  = { enabled = false },  -- green/red shield via scutil
    mic  = { enabled = false },  -- click-to-mute
    lang = { enabled = false },  -- input source: EN / RU / …

    -- Both read Open-Meteo: no API key, no account. Location comes from
    -- CoreLocation, so nothing about where you are lives in this file.
    --   weather = { place = "Porto" }     -- name a city instead
    --   surf = { lat = .., lon = .. }     -- watch a break you are not at
    weather = { enabled = true },

    surf = {
        enabled = true,
        up = 1.5,                -- metres at which the chip lights up
    },

    -- Hosts come from ~/.ssh/config, resolved through `ssh -G`. Nothing to list
    -- here, which is the point: this file is public.
    --   filter = "hetzner"          -- lua pattern, narrows the discovered set
    --   hosts = { "alias", ... }    -- explicit list instead of discovery
    servers = { enabled = true },

    -- Follows whichever repo your shell is in, via the chpwd/precmd hook in
    -- .zshrc. Set `path` to pin it to one repo and ignore the hook instead.
    repo = {
        enabled = true,          -- repo · branch · dirty count · CI dot
        ci = true,               -- needs the gh CLI, authenticated
    },
    -- coming: next calendar event (wants icalBuddy or a Calendar.app bridge)
}

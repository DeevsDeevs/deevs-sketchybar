-- deevs-sketchybar user config.
-- Every widget is optional. Delete a block or set enabled = false and it is gone.
return {
    structure = "glass",     -- glass | islands | deck | mono
    palette   = "everforest",-- see palettes/
    glass     = 0.66,        -- bar translucency 0..1 (1 = opaque)

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
        eq_bars = 12,
        eq_height = 16,      -- px at full scale
        whitelist = { ["com.spotify.client"] = true, ["com.apple.Music"] = true },
    },

    system = {
        enabled = true,      -- cpu sparkline + ram + net in one cluster
    },

    herd = {
        enabled = true,      -- herdr agent fleet (needs: herdr)
        hosts = {
            { name = "local" },
            -- { name = "prod-1", ssh = "deevs@prod-1" },
        },
        poll = 5,            -- seconds
    },

    session = {
        enabled = true,      -- Session.app pomodoro (needs Session.app)
    },

    mood = false,            -- per-space accent colors

    volume   = { enabled = true },

    -- Sonar needs a copy of your audio, which means routing output through a
    -- multi-output aggregate (device + BlackHole). macOS gives aggregates no
    -- hardware volume, so the F-row volume keys stop working while it is on —
    -- the bar's own volume chip (click/scroll) keeps working either way.
    audio = {
        auto_route = true,   -- route through <device + BlackHole> so sonar hears music
        volume_keys = false, -- enable only if the media keys stop working while routed
    },
    battery  = { enabled = true },
    calendar = { enabled = true },

    -- small optional chips
    vpn = { enabled = false },              -- green/red shield via scutil
    mic = { enabled = false },              -- click-to-mute
    -- coming: repo sense, next event, weather, input language
}

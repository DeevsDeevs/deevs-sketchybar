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
        cover = true,        -- album art
        sonar = true,        -- cava spectrum (needs: cava + BlackHole loopback)
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
        poll = 5,            -- seconds, local; remote hosts poll at 3x
    },

    session = {
        enabled = true,      -- Session.app pomodoro (needs: Session.app)
        alias = "Session,Item-0",
    },

    mood = false,            -- per-space accent colors

    volume   = { enabled = true },

    -- Sonar needs a copy of your audio, which means routing output through a
    -- multi-output aggregate (device + BlackHole). macOS gives aggregates no
    -- hardware volume, so the F-row volume keys stop working while it is on —
    -- the bar's own volume chip (click/scroll) keeps working either way.
    audio = { auto_route = true },
    battery  = { enabled = true },
    calendar = { enabled = true },

    -- small optional chips
    vpn = { enabled = false },              -- green/red shield via scutil
    mic = { enabled = false },              -- click-to-mute
    -- coming: repo sense, next event, weather, input language
}

-- Every widget is optional: delete a block or set enabled = false.
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
        max = 20,            -- highest space index the bar can show; unused ones stay hidden
    },

    menus_swap = true,       -- click front app name: spaces ↔ app menus

    media = {
        enabled = true,
        side = "left",           -- "left" puts it left of the notch; "right" for the usual spot
        cover = true,        -- album art, controls in its popup
        sonar = true,        -- spectrum EQ (needs cava; see audio.auto_route)
        text_width = 150,    -- px; long titles scroll inside it
        eq_bars = 12,
        eq_height = 16,      -- px at full scale
        whitelist = { ["com.spotify.client"] = true, ["com.apple.Music"] = true },
    },

    -- host: "local" (or absent) · "selected" to follow the servers picker · an ssh alias
    system = {
        enabled = true,      -- cpu sparkline + ram + net
        host = "selected",
        poll = 5,            -- seconds, remote hosts only
    },

    herdr = {
        enabled = true,      -- agent fleet (needs the herdr CLI)
        host = "selected",
        poll = 5,            -- seconds
        -- tab = 1,          -- pin the terminal tab; found on its own unless set
        -- hosts is the untargeted list, ignored while host = "selected"
        -- hosts = { { name = "local" }, { name = "prod-1", ssh = "deevs@prod-1" } },
    },

    session = {
        enabled = true,      -- Session.app pomodoro
    },

    mood = true,             -- per-space accent colors

    volume   = { enabled = true },

    -- cava can only listen to an INPUT, hence routing output through BlackHole.
    audio = {
        auto_route = true,   -- route output through BlackHole so sonar can hear it
        volume_keys = true,  -- required with auto_route: the aggregate has no hardware volume
    },
    battery  = { enabled = true },
    calendar = { enabled = true },

    vpn  = { enabled = false },  -- shield via scutil
    mic  = { enabled = false },  -- click-to-mute
    lang = { enabled = false },  -- input source: EN / RU / …

    --   weather = { place = "Porto" }   -- name a city instead of CoreLocation
    --   surf = { lat = .., lon = .. }
    weather = { enabled = true },

    surf = {
        enabled = false,
        up = 1.5,                -- metres at which the chip lights up
    },

    -- hosts from ~/.ssh/config via `ssh -G`; filter = "pattern" or hosts = { ... } to narrow
    servers = {
        enabled = true,
        select = true,       -- chip picks the target host; without it, a dot per host
        default = "local",
    },

    -- Follows the shell's chpwd/precmd hook — nothing outside the shell can
    -- tell which pane has focus. Set `path` to pin one repo.
    repo = {
        enabled = false,         -- repo · branch · dirty count · CI dot
        ci = true,               -- needs the gh CLI, authenticated
    },
}

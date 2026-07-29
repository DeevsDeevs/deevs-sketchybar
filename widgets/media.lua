-- Now playing via helpers/media_stream.sh (event-driven, artwork as file path —
-- never push big payloads through the lua bridge). Optional cava sonar.
-- NOTE: "media_change" is a RESERVED sketchybar event name; we use media_update.
return function(ctx)
    local p, c = ctx.palette, ctx.config
    -- Tolerate `media = true` and a media block with keys left out: every
    -- lookup below has to survive the minimal config the README suggests.
    local media = type(c.media) == "table" and c.media or {}
    local whitelist = media.whitelist or {
        ["com.spotify.client"] = true,
        ["com.apple.Music"] = true,
    }

    -- Must search the same PATH sonar.sh pins, or a devbox/nix cava is
    -- invisible here (launchd hands sketchybar a bare PATH) and the EQ items
    -- are never created even though the helper would have found it.
    local function has_cava()
        local f = io.popen("PATH=/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"
            .. " command -v cava 2>/dev/null")
        local out = f and f:read("*a") or ""
        if f then f:close() end
        return out ~= ""
    end

    -- EQ: a cluster of thin bars whose heights are driven by helpers/sonar.sh
    local cover, eq_bars
    local EQ_N = media.eq_bars or 12
    local EQ_H = media.eq_height or 16
    if media.sonar and has_cava() then
        eq_bars = {}
        for i = 1, EQ_N do
            local bar = sbar.add("item", "media.eq." .. i, {
                position = "right",
                drawing = false,
                updates = true,
                width = 3,
                padding_left = 1,
                padding_right = 1,
                icon = { drawing = false },
                label = { drawing = false },
                background = {
                    drawing = true,
                    color = ctx.with_alpha(p.accent, 0.9),
                    height = 2,
                    corner_radius = 1,
                },
                y_offset = -(EQ_H // 2) + 1,
            })
            eq_bars[i] = bar
            table.insert(ctx.groups.right, bar.name)
        end
    end

    -- Right-position items lay out right-to-left in creation order, so the
    -- cover is created BEFORE the text it reveals: the hover expansion has to
    -- grow away from the cover. With the cover left of the text it gets pushed
    -- out from under the cursor mid-expand and enter/exit oscillate.
    if media.cover then
        cover = sbar.add("item", "media.cover", {
            position = "right",
            width = 32,
            background = { color = p.transparent },
            label = { drawing = false },
            icon = { drawing = false },
            drawing = false,
            updates = true,
            popup = { align = "center", horizontal = true },
        })
        table.insert(ctx.groups.right, cover.name)
    end

    -- Two-line stack: title low, artist high. Artist is the zero-width overlay
    -- so the two share one horizontal band, which means it has to be created
    -- AFTER title — a zero-width item draws from the same origin as whatever
    -- follows it, and with artist next to the cover its label rendered straight
    -- across the album art. Both collapse to 0 and expand on hover.
    local title = sbar.add("item", "media.title", {
        position = "right",
        drawing = false,
        updates = true,
        padding_left = 3,
        padding_right = 0,
        icon = { drawing = false },
        label = { font = { size = 11 }, width = 0, max_chars = 16, y_offset = -5 },
    })
    local artist = sbar.add("item", "media.artist", {
        position = "right",
        drawing = false,
        updates = true,
        padding_left = 3,
        padding_right = 0,
        width = 0,
        icon = { drawing = false },
        label = {
            width = 0,
            font = { size = 9 },
            color = ctx.with_alpha(p.fg, 0.6),
            max_chars = 18,
            y_offset = 6,
        },
    })
    table.insert(ctx.groups.right, title.name)
    table.insert(ctx.groups.right, artist.name)

    local mc = "PATH=/opt/homebrew/bin:$PATH media-control "
    local animate_detail = function() end   -- no-op unless the cover exists
    if cover then
        for _, action in ipairs({
            { icon = "󰒮", cmd = "previous-track" },
            { icon = "󰐎", cmd = "toggle-play-pause" },
            { icon = "󰒭", cmd = "next-track" },
        }) do
            sbar.add("item", {
                position = "popup." .. cover.name,
                icon = { string = action.icon },
                label = { drawing = false },
                click_script = mc .. action.cmd,
            })
        end

        -- Plain boolean rather than a counter: the cover stops drawing when
        -- playback stops, and a hidden item never delivers the matching
        -- mouse.exited, so a counter latches and the text stays expanded.
        local expanded = false
        animate_detail = function(detail)
            if detail == expanded then return end
            expanded = detail
            sbar.animate("tanh", 20, function()
                artist:set({ label = { width = detail and "dynamic" or 0 } })
                title:set({ label = { width = detail and "dynamic" or 0 } })
            end)
        end

        cover:subscribe("mouse.entered", function() animate_detail(true) end)
        cover:subscribe("mouse.exited", function() animate_detail(false) end)
        cover:subscribe("mouse.clicked", function()
            cover:set({ popup = { drawing = "toggle" } })
        end)
        title:subscribe("mouse.exited.global", function()
            cover:set({ popup = { drawing = false } })
        end)
    else
        title:set({ label = { width = "dynamic" } })
        artist:set({ label = { width = "dynamic" } })
    end

    -- One slab across the whole media cluster, hidden with it: the eq bars and
    -- cover only draw while something is playing.
    local members = {}
    for _, bar in ipairs(eq_bars or {}) do table.insert(members, bar.name) end
    if cover then table.insert(members, cover.name) end
    table.insert(members, artist.name)
    table.insert(members, title.name)
    local backdrop = ctx.chip("media.chip", members, { drawing = false })

    local anchor = cover or title
    local has_art = nil
    sbar.add("event", "media_update")
    -- Picking an output used to fire system_woke, which six widgets listen to:
    -- it restarted the media stream (blanking the chip for its 5s startup wait)
    -- and orphaned another adapter every time. Only the sonar cares, because
    -- cava's source moves with the route.
    sbar.add("event", "audio_route_changed")

    -- media-control execs into a perl adapter, so the old "media-control
    -- stream" pattern matched nothing and every reload/wake orphaned another
    -- ~17MB subscriber onto launchd. Match what actually runs.
    local function start_stream()
        sbar.exec("pkill -f 'helpers/media_stream[.]sh' >/dev/null 2>&1;"
            .. " pkill -f 'mediaremote-adapte[r]' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("media_stream.sh"))))
    end

    local function start_sonar()
        if not eq_bars then return end
        -- Scoped to our own config dir: a bare `cava` pattern would also kill
        -- a cava the user is running in a terminal.
        sbar.exec("pkill -f 'helpers/sonar[.]sh' >/dev/null 2>&1;"
            .. " pkill -f 'sonar-cava[.]' >/dev/null 2>&1; "
            -- `env` rather than a bare VAR=… prefix: the detach wrapper execs.
            .. ctx.detached("env SONAR_BARS=" .. EQ_N .. " SONAR_HEIGHT=" .. EQ_H
                .. " " .. ctx.shell_quote(ctx.helper("sonar.sh"))))
    end

    start_stream()
    start_sonar()
    anchor:subscribe("system_woke", function()
        start_stream()
        start_sonar()
    end)
    anchor:subscribe("audio_route_changed", start_sonar)

    anchor:subscribe("media_update", function(env)
        local playing = env.PLAYING == "true"
        local drawing = playing and whitelist[env.APP] or false

        backdrop:set({ drawing = drawing })
        artist:set({ drawing = drawing, label = env.ARTIST })
        title:set({ drawing = drawing, label = env.TITLE })
        if eq_bars then
            for _, bar in ipairs(eq_bars) do bar:set({ drawing = drawing }) end
        end

        if not cover then return end
        if not drawing then
            animate_detail(false)   -- hiding the cover cancels any hover state
            cover:set({ drawing = false, popup = { drawing = false } })
            has_art = nil
            return
        end
        -- Artwork arrives in its own event a moment after the title changes, so
        -- keying the image off the track left the previous song's cover on
        -- screen until the next one. Re-set it exactly when the helper reports
        -- new art — still never on every event, which is what stacked draw
        -- layers into the "fanned covers" artifact.
        cover:set({ drawing = true })
        if env.ART_NEW ~= "1" and has_art then return end
        local f = env.ART_PATH and io.open(env.ART_PATH, "r")
        if not f then return end
        f:close()
        has_art = true
        cover:set({
            background = {
                image = { string = env.ART_PATH, scale = 0.22, corner_radius = 6 },
                color = p.transparent,
            },
        })
    end)
end

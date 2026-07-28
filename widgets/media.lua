-- Now playing via helpers/media_stream.sh (event-driven, artwork as file path —
-- never push big payloads through the lua bridge). Optional cava sonar.
-- NOTE: "media_change" is a RESERVED sketchybar event name; we use media_update.
return function(ctx)
    local p, c = ctx.palette, ctx.config
    local media = c.media

    local function has_cava()
        local f = io.popen("command -v cava 2>/dev/null")
        local out = f and f:read("*a") or ""
        if f then f:close() end
        return out ~= ""
    end

    local cover, sonar
    if media.sonar and has_cava() then
        sonar = sbar.add("graph", "media.sonar", 30, {
            position = "right",
            drawing = false,
            updates = true,
            graph = { color = p.accent, fill_color = ctx.with_alpha(p.accent, 0.25) },
            background = { height = 22, color = p.transparent, drawing = true },
            icon = { drawing = false },
            label = { drawing = false },
        })
        table.insert(ctx.groups.right, sonar.name)
    end

    -- Two-line stack: title low, artist high; collapsed to width 0 by default,
    -- expands while hovering the cover.
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

    local mc = "PATH=/opt/homebrew/bin:$PATH media-control "
    if media.cover then
        cover = sbar.add("item", "media.cover", {
            position = "right",
            background = { color = p.transparent },
            label = { drawing = false },
            icon = { drawing = false },
            drawing = false,
            updates = true,
            popup = { align = "center", horizontal = true },
        })
        table.insert(ctx.groups.right, cover.name)

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

        local interrupt = 0
        local function animate_detail(detail)
            if not detail then interrupt = interrupt - 1 end
            if interrupt > 0 and not detail then return end
            artist:set({ label = { width = detail and "dynamic" or 0 } })
            title:set({ label = { width = detail and "dynamic" or 0 } })
        end

        cover:subscribe("mouse.entered", function()
            interrupt = interrupt + 1
            animate_detail(true)
        end)
        cover:subscribe("mouse.exited", function()
            animate_detail(false)
        end)
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
    table.insert(ctx.groups.right, title.name)
    table.insert(ctx.groups.right, artist.name)

    local anchor = cover or title
    sbar.add("event", "media_update")

    local function start_stream()
        sbar.exec("pkill -f 'sketchybar/helpers/media_stream.sh' >/dev/null 2>&1;"
            .. " pkill -f 'media-control stream' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("media_stream.sh"))))
    end

    local function start_sonar()
        if not sonar then return end
        sbar.exec("pkill -f 'sketchybar/helpers/sonar.sh' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("sonar.sh"))))
    end

    start_stream()
    start_sonar()
    anchor:subscribe("system_woke", function()
        start_stream()
        start_sonar()
    end)

    anchor:subscribe("media_update", function(env)
        local playing = env.PLAYING == "true"
        local drawing = playing and media.whitelist[env.APP] or false

        artist:set({ drawing = drawing, label = env.ARTIST })
        title:set({ drawing = drawing, label = env.TITLE })
        if sonar then sonar:set({ drawing = drawing }) end

        if not cover then return end
        if not drawing then
            cover:set({ drawing = false, popup = { drawing = false } })
            return
        end
        local f = env.ART_PATH and io.open(env.ART_PATH, "r")
        if f then
            f:close()
            cover:set({
                drawing = true,
                background = {
                    image = { string = env.ART_PATH, scale = 0.05, corner_radius = 6 },
                    color = p.transparent,
                },
            })
        else
            cover:set({ drawing = true })
        end
    end)
end

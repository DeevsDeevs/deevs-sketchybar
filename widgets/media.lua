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

    -- Fixed box, scrolling contents: sizing it to the title let a long one
    -- expand leftwards far enough to run under the notch.
    local TEXT_W = media.text_width or 150

    -- Icons have no max_chars, and the artist rides in the icon slot with width
    -- 0, so nothing bounds it — clip it here. utf8.offset rather than a byte
    -- sub, or an accented name gets cut mid-character.
    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and (str:sub(1, cut - 1) .. "…") or str
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

    -- Two-line stack: artist above, title below. They land on the same box only
    -- because both labels carry the SAME fixed width — item width = 0 does not
    -- collapse the artist, it just parks it beside the title at a different
    -- height, which reads as two ragged lines.
    --
    -- Alignment is per line and depends on whether the text fits: one that fits
    -- is right-aligned so it sits against the cover instead of being stranded
    -- at the far edge of the box, and one that does not is left-aligned and
    -- marqueed (see slide). sketchybar's own scroll_texts does not move the
    -- text — verified with a 62-char label in a 150px box, zero pixels of
    -- movement over six seconds, item and bar property alike.
    local function line(name, opts)
        local item = sbar.add("item", name, {
            position = "right",
            drawing = false,
            updates = true,
            width = opts.overlay and 0 or nil,
            padding_left = 0,
            padding_right = 0,
            icon = { drawing = false },
            label = {
                width = 0,
                align = "right",
                font = { size = opts.size },
                color = opts.color,
                padding_left = 0,
                padding_right = opts.pad,
                y_offset = opts.y,
            },
        })
        table.insert(ctx.groups.right, item.name)
        return item
    end

    -- JetBrainsMono is monospaced, so a character count is a good enough width.
    local function text_px(value, size)
        return (utf8.len(tostring(value or "")) or 0) * size * 0.60
    end

    -- Artist first so it is the zero-width overlay sitting on top of the title.
    local artist = line("media.artist", {
        overlay = true, size = 9, y = 6, pad = 10,
        color = ctx.with_alpha(p.fg, 0.6),
    })
    local title = line("media.title", { size = 11, y = -5, pad = 10, color = p.fg })

    -- Marquee: the label clips to its fixed width, so animating its left padding
    -- negative slides the rest of the title into view and back again. Runs only
    -- while the text is expanded and genuinely too long to fit.
    local overflow = 0
    local slide_out = false

    local function slide_reset()
        slide_out = false
        title:set({ label = { padding_left = 0 } })
    end

    local function slide_step()
        if overflow <= 0 then return slide_reset() end
        slide_out = not slide_out
        -- Frames scale with the distance so the glide holds a steady speed
        -- whatever the title's length, capped to finish inside the tick that
        -- started it. "sin" eases both ends; "linear" set off and stopped dead.
        local frames = math.max(70, math.min(160, math.floor(overflow * 2.6)))
        sbar.animate("sin", frames, function()
            title:set({ label = { padding_left = slide_out and -overflow or 0 } })
        end)
    end

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
            if not detail then
                slide_reset()
            else
                slide_step()
            end
            sbar.animate("tanh", 28, function()
                artist:set({ label = { width = detail and TEXT_W or 0 } })
                title:set({ label = { width = detail and TEXT_W or 0 } })
            end)
        end

        -- One leg of the marquee per tick; the slide itself takes ~1.5s of the
        -- 3s window, leaving the ends readable.
        title:set({ update_freq = 3 })
        title:subscribe("routine", function()
            if expanded then slide_step() end
        end)

        cover:subscribe("mouse.entered", function() animate_detail(true) end)
        cover:subscribe("mouse.exited", function() animate_detail(false) end)
        cover:subscribe("mouse.clicked", function()
            cover:set({ popup = { drawing = "toggle" } })
        end)
        title:subscribe("mouse.exited.global", function()
            cover:set({ popup = { drawing = false } })
        end)
    else
        artist:set({ label = { width = TEXT_W } })
        title:set({ label = { width = TEXT_W } })
    end

    -- The slab covers only the always-on part. Including the hover text made
    -- the bracket resize as the labels tweened, and a bracket recomputes its
    -- extent in one step, so the glass visibly jumped out from under the sonar
    -- while the text was still sliding. The text expands over the bar's own
    -- glass instead.
    local members = {}
    for _, bar in ipairs(eq_bars or {}) do table.insert(members, bar.name) end
    if cover then table.insert(members, cover.name) end
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

        -- A line that fits is right-aligned so it sits against the cover; one
        -- that does not is left-aligned and marqueed, because right-aligning it
        -- would pin the tail and hide the start.
        local title_px = text_px(env.TITLE, 11)
        overflow = math.max(0, math.ceil(title_px - TEXT_W))
        slide_reset()

        artist:set({
            drawing = drawing,
            label = {
                string = clip(env.ARTIST, 28),
                align = text_px(env.ARTIST, 9) > TEXT_W and "left" or "right",
            },
        })
        title:set({
            drawing = drawing,
            label = { string = env.TITLE, align = overflow > 0 and "left" or "right" },
        })
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

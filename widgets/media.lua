-- media_change is a RESERVED sketchybar event name (triggers on it are silently swallowed), hence media_update.
return function(ctx)
    local p, c = ctx.palette, ctx.config
    local media = type(c.media) == "table" and c.media or {}
    local whitelist = media.whitelist or {
        ["com.spotify.client"] = true,
        ["com.apple.Music"] = true,
    }

    -- launchd hands sketchybar a bare PATH; without sonar.sh's pins a devbox/nix cava is invisible.
    local function has_cava()
        local f = io.popen("PATH=/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/share/devbox/global/default/.devbox/nix/profile/default/bin:$PATH"
            .. " command -v cava 2>/dev/null")
        local out = f and f:read("*a") or ""
        if f then f:close() end
        return out ~= ""
    end

    local TEXT_W = media.text_width or 150

    -- `side = "left"` puts the cluster left of the notch. Items lay out away from
    -- their own edge, so the left side needs the creation order reversed: text,
    -- cover, eq — see the ordering note at each block below.
    local SIDE = media.side == "left" and "left" or "right"
    local GROUP = ctx.groups[SIDE]
    -- Text that fits hugs the cover rather than stranding itself at the far edge of
    -- the box, and the cover is on the opposite side on each half of the bar.
    local FIT_ALIGN = SIDE == "right" and "right" or "left"
    local function place(item)
        table.insert(GROUP, item.name)
        return item
    end

    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and (str:sub(1, cut - 1) .. "…") or str
    end

    local cover, eq_bars
    local EQ_N = media.eq_bars or 12
    local EQ_H = media.eq_height or 16

    -- The lines share one box only because both labels carry the SAME fixed width; item width=0 does not collapse.
    local function line(name, opts)
        return place(sbar.add("item", name, {
            position = SIDE,
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
        }))
    end

    local function text_px(value, size)
        return (utf8.len(tostring(value or "")) or 0) * size * 0.60
    end

    -- EQ bar heights are driven externally by helpers/sonar.sh.
    local function add_eq()
        if not (media.sonar and has_cava()) then return end
        eq_bars = {}
        for i = 1, EQ_N do
            eq_bars[i] = place(sbar.add("item", "media.eq." .. i, {
                position = SIDE,
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
            }))
        end
    end

    -- Cover before the text on the right, after it on the left: either way the hover
    -- expansion grows away from the cover rather than dragging it out from under the pointer.
    local function add_cover()
        if not media.cover then return end
        cover = place(sbar.add("item", "media.cover", {
            position = SIDE,
            width = 32,
            background = { color = p.transparent },
            label = { drawing = false },
            icon = { drawing = false },
            drawing = false,
            updates = true,
            popup = { align = "center", horizontal = true },
        }))
    end

    local artist, title
    local function add_text()
        artist = line("media.artist", {
            overlay = true, size = 9, y = 6, pad = 10,
            color = ctx.with_alpha(p.fg, 0.6),
        })
        title = line("media.title", { size = 11, y = -5, pad = 10, color = p.fg })
    end

    -- Same order for both sides, and it mirrors for free: items lay out away from
    -- their own edge, so eq/cover/text reads text-cover-eq on the right and
    -- eq-cover-text on the left. What matters is that the text is created LAST, so
    -- the hover expansion grows into empty space. Created first, it shoves the cover
    -- out from under the pointer, which exits, collapses, re-enters and oscillates.
    add_eq(); add_cover(); add_text()

    -- On the left the hover expansion pushes the cluster toward the notch, and the
    -- room left of it shrinks with every space chip. Measure it instead of trusting
    -- a fixed width; the marquee covers whatever does not fit.
    local WANT_W = TEXT_W
    local function fit()
        if SIDE ~= "left" then return end
        sbar.exec(string.format("%s %d",
            ctx.shell_quote(ctx.helper("media_fit.sh")),
            32 + EQ_N * 5), function(out)
            local px = tonumber(tostring(out):match("%d+"))
            if px then TEXT_W = math.min(WANT_W, px) end
        end)
    end

    -- scroll_texts does not move text; the marquee animates the clipped label's padding_left.
    local overflow = 0
    local slide_out = false

    local function slide_reset()
        slide_out = false
        title:set({ label = { padding_left = 0 } })
    end

    local function slide_step()
        if overflow <= 0 then return slide_reset() end
        slide_out = not slide_out
        local frames = math.max(70, math.min(160, math.floor(overflow * 2.6)))
        sbar.animate("sin", frames, function()
            title:set({ label = { padding_left = slide_out and -overflow or 0 } })
        end)
    end

    local mc = "PATH=/opt/homebrew/bin:$PATH media-control "
    local animate_detail = function() end
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

        -- A hidden item never delivers mouse.exited, so a counter would latch; boolean.
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

    -- A bracket resizes in one step; including the tweening labels made the glass visibly jump.
    local members = {}
    for _, bar in ipairs(eq_bars or {}) do table.insert(members, bar.name) end
    if cover then table.insert(members, cover.name) end
    local backdrop = ctx.chip("media.chip", members, { drawing = false })

    local anchor = cover or title
    local has_art = nil
    sbar.add("event", "media_update")
    sbar.add("event", "audio_route_changed")

    -- media-control execs into a perl adapter; without the adapter pkill every reload leaks a subscriber.
    local function start_stream()
        sbar.exec("pkill -f 'helpers/media_stream[.]sh' >/dev/null 2>&1;"
            .. " pkill -f 'mediaremote-adapte[r]' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("media_stream.sh"))))
    end

    local function start_sonar()
        if not eq_bars then return end
        sbar.exec("pkill -f 'helpers/sonar[.]sh' >/dev/null 2>&1;"
            .. " pkill -f 'sonar-cava[.]' >/dev/null 2>&1; "
            -- `env` rather than a bare VAR=… prefix: the detach wrapper execs.
            .. ctx.detached("env SONAR_BARS=" .. EQ_N .. " SONAR_HEIGHT=" .. EQ_H
                .. " " .. ctx.shell_quote(ctx.helper("sonar.sh"))))
    end

    start_stream()
    start_sonar()
    fit()
    anchor:subscribe("space_change", fit)
    anchor:subscribe("system_woke", function()
        start_stream()
        start_sonar()
        fit()
    end)
    anchor:subscribe("audio_route_changed", start_sonar)

    anchor:subscribe("media_update", function(env)
        local playing = env.PLAYING == "true"
        local drawing = playing and whitelist[env.APP] or false

        backdrop:set({ drawing = drawing })

        local title_px = text_px(env.TITLE, 11)
        overflow = math.max(0, math.ceil(title_px - TEXT_W))
        slide_reset()

        artist:set({
            drawing = drawing,
            label = {
                string = clip(env.ARTIST, 28),
                align = text_px(env.ARTIST, 9) > TEXT_W and "left" or FIT_ALIGN,
            },
        })
        title:set({
            -- Overflowing text must be left-aligned; the marquee slides padding_left.
            drawing = drawing,
            label = { string = env.TITLE, align = overflow > 0 and "left" or FIT_ALIGN },
        })
        if eq_bars then
            for _, bar in ipairs(eq_bars) do bar:set({ drawing = drawing }) end
        end

        if not cover then return end
        if not drawing then
            animate_detail(false)
            cover:set({ drawing = false, popup = { drawing = false } })
            has_art = nil
            return
        end
        -- Setting the image on every event stacks draw layers ("fanned covers"): only re-set on new art.
        cover:set({ drawing = true })

        if env.ART_PATH == nil or env.ART_PATH == "" then
            if has_art then
                cover:set({ background = { image = { drawing = false }, color = p.transparent } })
                has_art = nil
            end
            return
        end

        if env.ART_NEW ~= "1" and has_art then return end
        local f = io.open(env.ART_PATH, "r")
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

-- No menubar alias: a hidden menubar item aliases as a blank region; state comes from session_stream.sh instead.
return function(ctx)
    local p = ctx.palette

    -- Progress lives in the icon: background.clip only applies to images and a slider claims its own slot.
    local PIE = { "󰝦", "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" }
    local STACK_W = 72   -- fits a 14-char intent at 8pt

    -- Right items lay out RIGHT-TO-LEFT in creation order: icon created last lands leftmost.
    local time = sbar.add("item", "session.time", {
        position = "right",
        width = 0,
        y_offset = 5,
        drawing = false,
        icon = { drawing = false },
        label = {
            string = "--:--",
            font = { family = ctx.settings.font.numbers, size = 10.5 },
            -- Both labels need the SAME fixed width to stack on one box.
            width = STACK_W,
            align = "left",
            padding_left = 0,
            padding_right = 0,
        },
    })
    local name = sbar.add("item", "session.name", {
        position = "right",
        y_offset = -6,
        drawing = false,
        update_freq = 3,
        icon = { drawing = false },
        label = {
            string = "",
            font = { family = ctx.settings.font.text, size = 8.0 },
            color = ctx.with_alpha(p.fg, 0.55),
            max_chars = 14,
            width = STACK_W,
            align = "left",
            padding_left = 0,
            padding_right = 0,
        },
    })
    local icon = sbar.add("item", "session.icon", {
        position = "right",
        drawing = false,
        icon = { string = PIE[1], color = p.accent, font = { size = 14.0 }, padding_right = 5 },
        label = { drawing = false },
        update_freq = 1,
        -- updates defaults to when_shown: an undrawn item gets no routine and could never turn itself back on.
        updates = true,
        popup = { align = "center", horizontal = true },
    })

    local bracket = ctx.chip("session.bracket", { icon.name, time.name, name.name }, { drawing = false })

    table.insert(ctx.groups.right, time.name)
    table.insert(ctx.groups.right, name.name)
    table.insert(ctx.groups.right, icon.name)

    local close = "; sketchybar --set " .. icon.name .. " popup.drawing=off"

    for _, action in ipairs({
        { glyph = "󰏤", link = "session:///pause" },
        { glyph = "󰅶", link = "session:///break" },
        { glyph = "󰄬", link = "session:///finish", color = p.good },
        { glyph = "󰅖", link = "session:///abandon", color = p.bad },
        { glyph = "󰑐", link = "session:///start-previous" },
    }) do
        sbar.add("item", {
            position = "popup." .. icon.name,
            icon = {
                string = action.glyph,
                font = { size = 14.0 },
                color = action.color or ctx.with_alpha(p.fg, 0.8),
                padding_left = 8,
                padding_right = 8,
            },
            label = { drawing = false },
            click_script = "open " .. ctx.shell_quote(action.link) .. close,
        })
    end
    local stats = sbar.add("item", {
        position = "popup." .. icon.name,
        drawing = false,
        icon = { drawing = false },
        label = {
            font = { family = ctx.settings.font.numbers, size = 9.0 },
            color = ctx.with_alpha(p.fg, 0.5),
            padding_left = 8,
            padding_right = 10,
        },
    })

    local deadline, total, kind = nil, nil, nil
    local absent = false

    -- scroll_texts does not move text; the marquee animates the clipped label's padding_left.
    local intent, hovering, slide_out = "", false, false

    local function name_px(value)
        return (utf8.len(tostring(value or "")) or 0) * 8.0 * 0.60
    end

    local function slide_reset()
        slide_out = false
        name:set({ label = { padding_left = 0, max_chars = 14, string = intent } })
    end

    local function slide_step()
        local over = math.ceil(name_px(intent) - STACK_W)
        if over <= 0 then return end
        slide_out = not slide_out
        local frames = math.max(70, math.min(160, math.floor(over * 2.6)))
        sbar.animate("sin", frames, function()
            name:set({ label = { padding_left = slide_out and -over or 0 } })
        end)
    end

    -- Drop max_chars while hovering, or the marquee only walks the truncated 14 chars.
    local function hover(on)
        if on == hovering then return end
        hovering = on
        if not on then return slide_reset() end
        name:set({ label = { max_chars = 0, string = intent } })
        slide_step()
    end

    local function show(state)
        local present = state ~= "absent"
        -- Undrawn items never deliver mouse.exited, so hover would latch on.
        if state ~= "running" then hover(false) end
        icon:set({ drawing = present })
        bracket:set({ drawing = present })
        time:set({ drawing = state == "running" })
        name:set({ drawing = state == "running" })
        if state ~= "running" then
            icon:set({ icon = { string = PIE[1], color = ctx.with_alpha(p.fg, 0.4) } })
        end
        if not present then icon:set({ popup = { drawing = false } }) end
    end

    local function tick()
        if absent then return end
        if not deadline then return show("idle") end
        local left = deadline - os.time()
        if left < 0 then
            deadline = nil
            return show("idle")
        end
        local done = total and total > 0 and (1 - left / total) or 0
        local accent = kind == "rest" and p.accent2 or p.accent
        local str = left >= 3600
            and string.format("%dh%02d", left // 3600, (left % 3600) // 60)
            or string.format("%d:%02d", left // 60, left % 60)
        icon:set({ icon = { string = PIE[math.floor(done * 8 + 0.5) + 1], color = accent } })
        time:set({ label = { string = str, color = accent } })
        show("running")
    end

    -- Push, never poll: sbar.exec callbacks stop arriving after a few minutes of polling.
    local function apply(env)
        if env.STATE == "absent" then
            deadline, total, kind, absent = nil, nil, nil, true
            return show("absent")
        end
        absent = false
        if env.TODAY_N then
            local mins = tonumber(env.TODAY_MIN) or 0
            stats:set({
                drawing = true,
                label = string.format("today %s · %dh %02dm",
                    env.TODAY_N, math.floor(mins / 60), mins % 60),
            })
        end
        if env.STATE ~= "run" then
            deadline, total, kind = nil, nil, nil
            return show("idle")
        end
        deadline = os.time() + (tonumber(env.LEFT) or 0)
        total, kind = tonumber(env.TOTAL), env.KIND
        intent = (env.TITLE ~= "" and env.TITLE) or "focus"
        if hovering then
            name:set({ label = { max_chars = 0, string = intent } })
        else
            slide_reset()
        end
        tick()
    end

    sbar.add("event", "session_update")
    icon:subscribe("session_update", apply)
    icon:subscribe({ "routine", "forced" }, tick)

    local function start_stream()
        sbar.exec("pkill -f 'helpers/session_stream[.]sh' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("session_stream.sh"))))
    end
    start_stream()
    icon:subscribe("system_woke", start_stream)

    local function open_popup()
        icon:set({ popup = { drawing = "toggle" } })
    end

    name:subscribe("routine", function()
        if hovering then slide_step() end
    end)

    for _, item in ipairs({ icon, time, name }) do
        item:subscribe("mouse.clicked", open_popup)
        item:subscribe("mouse.entered", function() hover(true) end)
        item:subscribe("mouse.exited", function() hover(false) end)
        item:subscribe("mouse.exited.global", function()
            hover(false)
            icon:set({ popup = { drawing = false } })
        end)
    end
end

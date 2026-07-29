-- Session.app pomodoro. State comes from helpers/session_query.sh, which reads
-- the live block from Session's preferences — the sqlite only gets a task row
-- once a block finishes, so it can never see what is running now.
-- Controls via session:/// deep links. No alias — with the native menubar
-- hidden, aliases capture a blank region.
--
-- Layout mirrors the media cluster: a pie icon that fills as the session
-- burns down, and a two-line stack of countdown over intent name. The stack
-- is the zero-width overlay trick used by the network rows.
return function(ctx)
    local p, style = ctx.palette, ctx.style

    -- 0/8 … 8/8 — progress lives in the icon, since sketchybar can't draw a
    -- background under a chip (background.clip only applies to images, and a
    -- slider always claims its own slot however narrow the item is).
    local PIE = { "󰝦", "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" }
    local STACK_W = 72   -- fits a 14-char intent at 8pt

    -- All the digging lives in helpers/session_query.sh. Long inline shell
    -- strings proved unreliable through sbar.exec: the same query would return
    -- an empty payload every few polls and blank the chip.
    local query = ctx.shell_quote(ctx.helper("session_query.sh"))

    -- Countdown first and zero-width so the name below governs the width;
    -- the icon is created last so it lands to the left of the stack.
    local time = sbar.add("item", "session.time", {
        position = "right",
        width = 0,
        y_offset = 5,
        drawing = false,
        icon = { drawing = false },
        label = {
            string = "--:--",
            font = { family = ctx.settings.font.numbers, size = 10.5 },
            -- Both lines share a fixed left-aligned box so they stack flush and
            -- the chip keeps its width when the intent changes.
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
        -- Must keep ticking while hidden: the default when_shown stops routine
        -- events for an undrawn item, so once a session ended the chip would
        -- never poll again and could never come back.
        updates = true,
        popup = { align = "center", horizontal = true },
    })

    local bracket = sbar.add("bracket", "session.bracket", { icon.name, time.name, name.name }, {
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        drawing = false,
    })

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
        icon = { drawing = false },
        label = {
            string = "…",
            font = { family = ctx.settings.font.numbers, size = 9.0 },
            color = ctx.with_alpha(p.fg, 0.5),
            padding_left = 8,
            padding_right = 10,
        },
    })

    local deadline, total, kind = nil, nil, nil

    -- Three states: running (ring + countdown + intent), idle (an empty ring
    -- you can still click to start something), and absent — the chip only
    -- disappears when Session itself isn't installed.
    local function show(state)
        local present = state ~= "absent"
        icon:set({ drawing = present })
        bracket:set({ drawing = present })
        time:set({ drawing = state == "running" })
        name:set({ drawing = state == "running" })
        if state ~= "running" then
            icon:set({ icon = { string = PIE[1], color = ctx.with_alpha(p.fg, 0.4) } })
        end
        if not present then icon:set({ popup = { drawing = false } }) end
    end

    -- Rendered every second from cached values; sqlite is only re-read
    -- periodically, so the countdown costs nothing between polls.
    local function tick()
        if not deadline then return show("idle") end
        local left = deadline - os.time()
        if left < 0 then
            deadline = nil
            return show("idle")
        end
        local done = total and total > 0 and (1 - left / total) or 0
        local accent = kind == "rest" and p.accent2 or p.accent
        -- Focus blocks here regularly run past an hour, so plain mm:ss would
        -- read as "119:05"; the h marker keeps the two forms distinct.
        local str = left >= 3600
            and string.format("%dh%02d", left // 3600, (left % 3600) // 60)
            or string.format("%d:%02d", left // 60, left % 60)
        icon:set({ icon = { string = PIE[math.floor(done * 8 + 0.5) + 1], color = accent } })
        time:set({ label = { string = str, color = accent } })
        show("running")
    end

    local function poll()
        sbar.exec(query .. " current", function(out)
            local reply = tostring(out)
            if reply:match("^NODB") then
                deadline, total, kind = nil, nil, nil
                return show("absent")
            end
            if reply:match("^IDLE") then
                deadline, total, kind = nil, nil, nil
                return show("idle")
            end
            local left, tot, ztype, zname = reply:match("^RUN\t(%-?%d+)\t(%d+)\t([^\t]*)\t(.-)%s*$")
            -- Anything else is a dropped or crossed payload, not evidence that
            -- Session is idle: keep counting down from the cached deadline
            -- instead of blanking the chip.
            if not left then return end
            deadline = os.time() + tonumber(left)
            total, kind = tonumber(tot), ztype
            name:set({ label = { string = (zname ~= "" and zname or "focus") } })
            tick()
        end)
    end

    local ticks = 0
    icon:subscribe({ "routine", "forced" }, function()
        ticks = ticks + 1
        if ticks % 20 == 0 then poll() else tick() end
    end)
    icon:subscribe("system_woke", poll)
    poll()

    local function open_popup()
        sbar.exec(query .. " today",
            function(out)
                local n, mins = tostring(out):match("(%d+)\t(%d+)")
                if n then
                    stats:set({ label = string.format("today %d · %dh %02dm",
                        tonumber(n), math.floor(mins / 60), mins % 60) })
                end
            end)
        icon:set({ popup = { drawing = "toggle" } })
    end

    for _, item in ipairs({ icon, time, name }) do
        item:subscribe("mouse.clicked", open_popup)
        item:subscribe("mouse.exited.global", function()
            icon:set({ popup = { drawing = false } })
        end)
    end
end

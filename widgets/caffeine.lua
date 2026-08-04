return function(ctx)
    ctx.owns_popup()
    local p = ctx.palette
    local conf = type(ctx.config.caffeine) == "table" and ctx.config.caffeine or {}
    local helper = ctx.shell_quote(ctx.helper("caffeine.sh"))
    local durations = conf.durations or { 15, 30, 60, 120 }

    local function pretty(minutes)
        if minutes < 60 then return string.format("%dm", minutes) end
        local hours, rest = minutes // 60, minutes % 60
        return rest == 0 and string.format("%dh", hours)
            or string.format("%dh%02d", hours, rest)
    end

    local caffeine = sbar.add("item", "widgets.caffeine", {
        position = "right",
        icon = {
            string = "\u{f0176}",
            font = { size = 14.0 },
            color = ctx.with_alpha(p.fg, 0.5),
        },
        label = {
            drawing = false,
            font = { family = ctx.settings.font.numbers },
            color = p.accent,
            padding_left = 3,
        },
        popup = { align = "center" },
        updates = true,
    })
    table.insert(ctx.groups.right, caffeine.name)
    ctx.cluster("status", caffeine.name)

    local awake = false

    -- `left` is nil for an indefinite hold: there is nothing to count down, so the cup
    -- lights on its own and the routine stays off until a timed hold needs it.
    local function render(left)
        caffeine:set({
            icon = { color = awake and p.accent or ctx.with_alpha(p.fg, 0.5) },
            label = {
                drawing = left ~= nil,
                string = left and pretty(math.max(1, math.ceil(left / 60))) or "",
            },
            update_freq = left and 1 or 0,
        })
    end

    local function sync()
        sbar.exec(string.format("%s status", helper), function(out)
            local reply = tostring(out)
            awake = reply:match("^on") ~= nil
            if not awake then return render(nil) end
            local left = tonumber(reply:match("on%s+(%d+)"))
            render(left)
        end)
    end

    -- Asked for rather than assumed, so a reload while the Mac is held awake picks the
    -- state back up instead of showing a cold cup over a live caffeinate.
    caffeine:subscribe({ "routine", "forced", "system_woke" }, sync)
    sync()

    for _, minutes in ipairs(durations) do
        local row = sbar.add("item", {
            position = "popup." .. caffeine.name,
            icon = { drawing = false },
            label = {
                string = pretty(minutes),
                font = { family = ctx.settings.font.numbers },
                padding_left = 12,
                padding_right = 12,
            },
        })
        row:subscribe("mouse.clicked", function()
            sbar.exec(string.format("%s on %d", helper, minutes), sync)
            caffeine:set({ popup = { drawing = false } })
        end)
    end

    caffeine:subscribe("mouse.clicked", function(env)
        if env.BUTTON == "right" then
            return caffeine:set({ popup = { drawing = "toggle" } })
        end
        sbar.exec(string.format("%s %s", helper, awake and "off" or "on"), sync)
    end)
    caffeine:subscribe("mouse.exited.global", function()
        caffeine:set({ popup = { drawing = false } })
    end)
end

-- Hosts are herdr's saved machines (`herdr machine add <ssh-host>`), so the picker, the
-- system widget and the herdr popup share one list. Each row carries the machine's ssh
-- target, which is what the system widget dials.
return function(ctx)
    ctx.owns_popup()
    local p = ctx.palette
    local cfg = ctx.config.servers or {}
    local idle = ctx.with_alpha(p.fg, 0.25)

    -- Synchronous: the bracket is built the moment this returns, so an async reply could not add dots later.
    -- Columns: id, label, ssh target, session, enabled.
    local hosts = {}
    local pipe = io.popen("herdr machine list 2>/dev/null", "r")
    if pipe then
        for line in pipe:read("a"):gmatch("[^\n]+") do
            local label, target, state = line:match("^%x+\t([^\t]+)\t([^\t]+)\t[^\t]*\t(%a+)$")
            if label and state == "enabled" then
                hosts[#hosts + 1] = { alias = target, label = label }
            end
        end
        pipe:close()
    end
    if #hosts == 0 then return end

    -- Selector mode: the chip names one target instead of reporting every host at once.
    local select = cfg.select == true
    if select then
        table.insert(hosts, 1, { alias = "local", local_host = true })
    end

    -- Right-position items lay out right-to-left in creation order: dots reversed, icon last to sit leftmost.
    local dots, rows = {}, {}
    if not select then
        for i = #hosts, 1, -1 do
            dots[i] = sbar.add("item", "widgets.servers.dot." .. i, {
                position = "right",
                icon = { string = "\u{f0765}", font = { size = 9.0 }, color = idle },
                label = { drawing = false },
                padding_left = 1,
                padding_right = 1,
            })
            table.insert(ctx.groups.right, dots[i].name)
            ctx.cluster("servers", dots[i].name)
        end
    end

    local target = select and (cfg.default or "local") or nil

    local servers = sbar.add("item", "widgets.servers", {
        position = "right",
        icon = { string = "\u{f048d}", font = { size = 12.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = {
            drawing = select,
            string = select and target or "",
            font = { family = ctx.settings.font.text, size = 11.5 },
            color = ctx.with_alpha(p.fg, 0.85),
            padding_left = 4,
        },
        update_freq = 60,
        popup = { align = "center" },
    })
    table.insert(ctx.groups.right, servers.name)
    ctx.cluster("servers", servers.name)

    local function name_of(alias)
        for _, h in ipairs(hosts) do
            if h.alias == alias then return h.label or h.alias end
        end
        return alias
    end
    -- JetBrainsMono advances ~7.8px/char at 13px; size to the longest name so names never clip.
    local longest = 0
    for _, h in ipairs(hosts) do longest = math.max(longest, #(h.label or h.alias)) end
    local name_width = math.max(90, math.ceil(longest * 7.8) + 8)

    for i, h in ipairs(hosts) do
        rows[i] = sbar.add("item", "widgets.servers.row." .. i, {
            position = "popup." .. servers.name,
            icon = { string = h.label or h.alias, width = name_width, align = "left" },
            label = {
                string = h.local_host and "here" or "···",
                width = 50, align = "right", color = idle,
            },
            click_script = select and ("sketchybar --trigger host_change HOST="
                .. ctx.shell_quote(h.alias)
                .. " --set widgets.servers popup.drawing=off") or nil,
        })
    end

    -- herdr checks every machine over its own ssh, including ones behind a ProxyCommand
    -- that a bare TCP probe cannot reach. Lines: id, label, status.
    local probe = "herdr machine status 2>/dev/null"

    local reachable = {}

    -- The chip is the only dot in select mode, so it carries the target's reachability.
    local function paint_chip()
        if not select then return end
        local up = reachable[target]
        servers:set({
            icon = { color = up == false and p.bad
                or up == true and p.good
                or ctx.with_alpha(p.fg, 0.7) },
            label = { string = name_of(target) },
        })
        for i, h in ipairs(hosts) do
            rows[i]:set({ icon = { color = h.alias == target and p.accent or p.fg } })
        end
    end

    local function paint(i, up)
        reachable[hosts[i].alias] = up
        if dots[i] then dots[i]:set({ icon = { color = up and p.good or p.bad } }) end
        rows[i]:set({ label = { string = up and "up" or "down",
            color = up and p.good or p.bad } })
    end

    local function apply(out)
        local seen = {}
        -- The exec response arrives un-NUL-terminated; anchored per-line match rejects the garbage tail.
        for line in tostring(out):gmatch("[^\n]+") do
            local label, state = line:match("^%x+\t([^\t]+)\t(%S+)$")
            for i, h in ipairs(hosts) do
                if label and h.label == label then
                    seen[i] = true
                    paint(i, state == "reachable")
                end
            end
        end
        for i, h in ipairs(hosts) do
            if not seen[i] and not h.local_host then
                reachable[h.alias] = nil
                if dots[i] then dots[i]:set({ icon = { color = idle } }) end
                rows[i]:set({ label = { string = "···", color = idle } })
            end
        end
        paint_chip()
    end

    local function refresh() sbar.exec(probe, apply) end

    servers:subscribe({ "routine", "forced", "system_woke" }, refresh)
    refresh()

    servers:subscribe("mouse.clicked", function()
        servers:set({ popup = { drawing = "toggle" } })
        refresh()
    end)
    servers:subscribe("mouse.exited.global", function()
        servers:set({ popup = { drawing = false } })
    end)

    -- Last, after the mouse subscriptions: subscribing an item to mouse events *after* a
    -- custom event silently drops the custom one, and the handler simply never fires.
    if select then
        sbar.add("event", "host_change")
        servers:subscribe("host_change", function(env)
            if env.HOST and env.HOST ~= "" then target = env.HOST end
            paint_chip()
        end)
        paint_chip()
    end
end

return function(ctx)
    local p = ctx.palette
    local conf = type(ctx.config.system) == "table" and ctx.config.system or {}
    local fixed, follows = ctx.host_of(conf)
    local target = fixed or (follows and ((ctx.config.servers or {}).default or "local")) or nil
    if target == "local" then target = nil end

    local net_up = sbar.add("item", "system.net.up", {
        position = "right",
        width = 0,
        y_offset = 4,
        icon = { drawing = false },
        label = {
            string = "↑ ---",
            font = { family = ctx.settings.font.numbers, size = 8.0 },
            color = ctx.with_alpha(p.fg, 0.55),
            padding_left = 0,
            padding_right = 0,
        },
        padding_left = 6,
    })
    local net_down = sbar.add("item", "system.net.down", {
        position = "right",
        y_offset = -4,
        icon = { drawing = false },
        label = {
            string = "↓ ---",
            font = { family = ctx.settings.font.numbers, size = 8.0 },
            color = ctx.with_alpha(p.accent2, 0.9),
            padding_left = 0,
            padding_right = 0,
        },
        padding_left = 6,
    })
    local ram = sbar.add("item", "system.ram", {
        position = "right",
        icon = {
            string = "󰘚",
            font = { size = 11.0 },
            color = ctx.with_alpha(p.fg, 0.6),
            padding_left = 0,
            padding_right = 3,
        },
        label = {
            string = "--",
            font = { family = ctx.settings.font.numbers, size = 10.0 },
            padding_left = 0,
            padding_right = 0,
        },
        update_freq = 10,
        padding_left = 6,
    })
    local cpu = sbar.add("graph", "system.cpu", 36, {
        position = "right",
        -- unset fill_color defaults to an opaque grey slab
        graph = { color = p.accent, fill_color = ctx.with_alpha(p.accent, 0.15), line_width = 1.0 },
        background = { height = 22, color = p.transparent, drawing = true },
        icon = { drawing = false },
        label = {
            string = "--%",
            font = { family = ctx.settings.font.numbers, size = 10.0 },
            padding_left = 4,
            padding_right = 0,
        },
    })

    ctx.chip("system.bracket", { cpu.name, ram.name, net_up.name, net_down.name })
    table.insert(ctx.groups.right, cpu.name)
    table.insert(ctx.groups.right, ram.name)
    table.insert(ctx.groups.right, net_up.name)
    table.insert(ctx.groups.right, net_down.name)

    local cpu_bin = ctx.helper("event_providers/cpu_load/bin/cpu_load")
    sbar.exec("killall cpu_load >/dev/null 2>&1; "
        .. ctx.detached(ctx.shell_quote(cpu_bin) .. " cpu_update 2.0"))
    local function show_cpu(load, text)
        local color = p.accent
        if load > 80 then color = p.bad
        elseif load > 55 then color = p.warn end
        cpu:push({ load / 100.0 })
        cpu:set({ graph = { color = color }, label = { string = (text or load) .. "%", color = color } })
    end

    cpu:subscribe("cpu_update", function(env)
        if target then return end
        show_cpu(tonumber(env.total_load) or 0, env.total_load)
    end)

    -- interface detected via io.popen, not sbar.exec: nested exec callbacks during config load get dropped
    local net_bin = ctx.helper("event_providers/network_load/bin/network_load")
    local ih = io.popen(ctx.shell_quote(ctx.helper("network_interface.sh")) .. " 2>/dev/null")
    local iface = ih and (ih:read("*a") or ""):gsub("%s+", "") or ""
    if ih then ih:close() end
    if iface == "" then iface = "en0" end
    sbar.exec("killall network_load >/dev/null 2>&1; "
        .. ctx.detached(ctx.shell_quote(net_bin) .. " " .. ctx.shell_quote(iface) .. " network_update 2.0"))
    -- width=0 does not collapse the up row: it still occupies its label width, overlaying the down row; aligned only because the numbers font is monospaced.
    local unit = { [" Bps"] = "B", ["KBps"] = "K", ["MBps"] = "M" }
    local function rate(raw)
        local n, u = tostring(raw or ""):match("^(%d+)(.*)$")
        if not n then return "  --" end
        return string.format("%3d%s", tonumber(n), unit[u] or u)
    end

    net_up:subscribe("network_update", function(env)
        if target then return end
        net_up:set({ label = "↑ " .. rate(env.upload) })
        net_down:set({ label = "↓ " .. rate(env.download) })
    end)

    -- vm_stat says "Pages occupied by compressor", not "Pages compressed".
    ram:subscribe({ "routine", "forced" }, function()
        if target then return end
        sbar.exec([[vm_stat | awk '/page size/{gsub(/[^0-9]/,"",$8); ps=$8} /Pages active/{a=$3} /Pages wired/{w=$4} /occupied by compressor/{c=$5} END{printf "%.0f", (a+w+c)*ps/1073741824}']],
            function(gb)
                ram:set({ label = tostring(gb):gsub("%s", "") .. "G" })
            end)
    end)

    -- Nothing remote can push into the bar, so the C providers feed the local path and
    -- a timed ssh poll feeds this one. Both stay live; `target` decides which paints.
    local driver = sbar.add("item", "system.remote", {
        position = "right",
        drawing = false,
        updates = true,
        update_freq = conf.poll or 5,
    })

    local function fetch()
        if not target then return end
        local asked = target
        sbar.exec(string.format("%s %s", ctx.shell_quote(ctx.helper("remote_perf.sh")),
            ctx.shell_quote(target)), function(out)
            if asked ~= target then return end
            local load, mem, up, down = tostring(out):match("(%d+) (%d+) (%d+) (%d+)")
            -- An unreachable host and an idle one must not read the same, and leaving the
            -- previous host's numbers up would attribute them to this one.
            if not load then
                cpu:set({ label = { string = "···", color = ctx.with_alpha(p.fg, 0.4) } })
                ram:set({ label = "--" })
                net_up:set({ label = "↑ " .. rate(nil) })
                net_down:set({ label = "↓ " .. rate(nil) })
                return
            end
            show_cpu(tonumber(load))
            ram:set({ label = mem .. "G" })
            net_up:set({ label = "↑ " .. rate(up .. "KBps") })
            net_down:set({ label = "↓ " .. rate(down .. "KBps") })
        end)
    end
    driver:subscribe({ "routine", "forced" }, fetch)

    if follows then
        sbar.add("event", "host_change")
        driver:subscribe("host_change", function(env)
            local pick = env.HOST
            if not pick or pick == "" then return end
            if pick == "local" then pick = nil end
            if pick == target then return end
            target = pick
            fetch()
        end)
    end
    fetch()

    cpu:subscribe("mouse.clicked", function()
        sbar.exec("open -a 'Activity Monitor'")
    end)
end

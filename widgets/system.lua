-- One system cluster: load-colored cpu sparkline + ram + net rates.
return function(ctx)
    local p, style = ctx.palette, ctx.style

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
        -- an unset fill_color is opaque light grey: the sparkline renders as a
        -- solid slab. Tint it from the line colour and thicken the line so the
        -- curve reads on top of its own fill.
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

    sbar.add("bracket", "system.bracket", { cpu.name, ram.name, net_up.name, net_down.name }, {
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
    })
    table.insert(ctx.groups.right, cpu.name)
    table.insert(ctx.groups.right, ram.name)
    table.insert(ctx.groups.right, net_up.name)
    table.insert(ctx.groups.right, net_down.name)

    -- cpu: C event provider (compiled by install.sh)
    local cpu_bin = ctx.helper("event_providers/cpu_load/bin/cpu_load")
    sbar.exec("killall cpu_load >/dev/null 2>&1; "
        .. ctx.detached(ctx.shell_quote(cpu_bin) .. " cpu_update 2.0"))
    cpu:subscribe("cpu_update", function(env)
        local load = tonumber(env.total_load) or 0
        cpu:push({ load / 100.0 })
        local color = p.accent
        if load > 80 then color = p.bad
        elseif load > 55 then color = p.warn end
        cpu:set({ graph = { color = color }, label = { string = env.total_load .. "%", color = color } })
    end)

    -- net: C event provider on the active interface (detected synchronously —
    -- nested exec callbacks during config load get dropped)
    local net_bin = ctx.helper("event_providers/network_load/bin/network_load")
    local ih = io.popen(ctx.shell_quote(ctx.helper("network_interface.sh")) .. " 2>/dev/null")
    local iface = ih and (ih:read("*a") or ""):gsub("%s+", "") or ""
    if ih then ih:close() end
    if iface == "" then iface = "en0" end
    sbar.exec("killall network_load >/dev/null 2>&1; "
        .. ctx.detached(ctx.shell_quote(net_bin) .. " " .. ctx.shell_quote(iface) .. " network_update 2.0"))
    -- The provider emits "%03d" plus a space-padded unit ("001KBps"). Trim both
    -- to match the ram value's shape (13G), then pad the number back out: the
    -- up row is a zero-width overlay on the down row, so the two only stay
    -- aligned while they render the same width — which holds because the
    -- numbers font is monospaced.
    local unit = { [" Bps"] = "B", ["KBps"] = "K", ["MBps"] = "M" }
    local function rate(raw)
        local n, u = tostring(raw or ""):match("^(%d+)(.*)$")
        if not n then return "  --" end
        return string.format("%3d%s", tonumber(n), unit[u] or u)
    end

    net_up:subscribe("network_update", function(env)
        net_up:set({ label = "↑ " .. rate(env.upload) })
        net_down:set({ label = "↓ " .. rate(env.download) })
    end)

    -- ram: cheap vm_stat poll. The compressor line is "Pages occupied by
    -- compressor" — matching "Pages compressed" silently matched nothing and
    -- under-reported by roughly half whenever memory was under pressure.
    ram:subscribe({ "routine", "forced" }, function()
        sbar.exec([[vm_stat | awk '/page size/{gsub(/[^0-9]/,"",$8); ps=$8} /Pages active/{a=$3} /Pages wired/{w=$4} /occupied by compressor/{c=$5} END{printf "%.0f", (a+w+c)*ps/1073741824}']],
            function(gb)
                ram:set({ label = tostring(gb):gsub("%s", "") .. "G" })
            end)
    end)

    cpu:subscribe("mouse.clicked", function()
        sbar.exec("open -a 'Activity Monitor'")
    end)
end

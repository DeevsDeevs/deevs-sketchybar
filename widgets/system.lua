-- One system cluster: load-colored cpu sparkline + ram + net rates.
return function(ctx)
    local p, style = ctx.palette, ctx.style

    local net = sbar.add("item", "system.net", {
        position = "right",
        icon = { drawing = false },
        label = {
            string = "↓ ---",
            font = { family = ctx.settings.font.numbers, size = 9.0 },
            color = ctx.with_alpha(p.fg, 0.65),
        },
        padding_left = 0,
    })
    local ram = sbar.add("item", "system.ram", {
        position = "right",
        icon = { string = "󰘚", font = { size = 11.0 }, color = ctx.with_alpha(p.fg, 0.6), padding_right = 2 },
        label = { string = "--", font = { family = ctx.settings.font.numbers, size = 10.0 } },
        update_freq = 10,
        padding_left = 0,
    })
    local cpu = sbar.add("graph", "system.cpu", 36, {
        position = "right",
        graph = { color = p.accent },
        background = { height = 22, color = p.transparent, drawing = true },
        icon = { drawing = false },
        label = {
            string = "--%",
            font = { family = ctx.settings.font.numbers, size = 9.0 },
            align = "right",
            padding_right = 4,
            width = 32,
            y_offset = 4,
        },
    })

    sbar.add("bracket", "system.bracket", { cpu.name, ram.name, net.name }, {
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
    })
    table.insert(ctx.groups.right, cpu.name)
    table.insert(ctx.groups.right, ram.name)
    table.insert(ctx.groups.right, net.name)

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
    net:subscribe("network_update", function(env)
        net:set({ label = "↑" .. (env.upload or "?") .. " ↓" .. (env.download or "?") })
    end)

    -- ram: cheap vm_stat poll
    ram:subscribe({ "routine", "forced" }, function()
        sbar.exec([[vm_stat | awk '/page size/{gsub(/[^0-9]/,"",$8); ps=$8} /Pages active/{a=$3} /Pages wired/{w=$4} /Pages compressed/{c=$5} END{printf "%.0f", (a+w+c)*ps/1073741824}']],
            function(gb)
                ram:set({ label = tostring(gb):gsub("%s", "") .. "G" })
            end)
    end)

    cpu:subscribe("mouse.clicked", function()
        sbar.exec("open -a 'Activity Monitor'")
    end)
end

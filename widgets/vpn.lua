return function(ctx)
    local p = ctx.palette

    local vpn = sbar.add("item", "widgets.vpn", {
        position = "right",
        icon = { string = "󰦝", font = { size = 12.0 } },
        label = { drawing = false },
        update_freq = 30,
    })
    table.insert(ctx.groups.right, vpn.name)

    vpn:subscribe({ "routine", "forced", "system_woke" }, function()
        -- Count only services actually reporting "(Connected)". The old probe
        -- also looked for an address on utun0, but macOS keeps a utun0 with an
        -- inet6 link-local up for Handoff/Private Relay on every Mac, so it
        -- reported connected forever whether or not a VPN existed.
        sbar.exec("scutil --nc list 2>/dev/null | grep -c '(Connected)'", function(out)
            local connected = (tonumber(tostring(out):match("%d+")) or 0) > 0
            vpn:set({ icon = { color = connected and p.good or ctx.with_alpha(p.fg, 0.35) } })
        end)
    end)
end

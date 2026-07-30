return function(ctx)
    local p = ctx.palette

    local vpn = sbar.add("item", "widgets.vpn", {
        position = "right",
        icon = { string = "󰦝", font = { size = 12.0 } },
        label = { drawing = false },
        update_freq = 30,
    })
    table.insert(ctx.groups.right, vpn.name)
    ctx.cluster("status", vpn.name)

    vpn:subscribe({ "routine", "forced", "system_woke" }, function()
        -- Not utun interfaces: every Mac keeps a utun0 up for Handoff/Private Relay, which reads as connected forever.
        sbar.exec("scutil --nc list 2>/dev/null | grep -c '(Connected)'", function(out)
            local connected = (tonumber(tostring(out):match("%d+")) or 0) > 0
            vpn:set({ icon = { color = connected and p.good or ctx.with_alpha(p.fg, 0.35) } })
        end)
    end)
end

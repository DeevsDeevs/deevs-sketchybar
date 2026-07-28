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
        sbar.exec("scutil --nc list 2>/dev/null | grep -c Connected; ifconfig utun0 2>/dev/null | grep -c inet", function(out)
            local connected = tostring(out):match("[1-9]") ~= nil
            vpn:set({ icon = { color = connected and p.good or p.bad } })
        end)
    end)
end

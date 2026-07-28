return function(ctx)
    local p, style = ctx.palette, ctx.style

    local battery = sbar.add("item", "widgets.battery", {
        position = "right",
        icon = { font = { size = 14.0 } },
        label = { font = { family = ctx.settings.font.numbers } },
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        update_freq = 180,
        popup = { align = "center" },
    })
    table.insert(ctx.groups.right, battery.name)

    local remaining = sbar.add("item", {
        position = "popup." .. battery.name,
        icon = { string = "time left", width = 90, align = "left" },
        label = { string = "??:??", width = 80, align = "right" },
    })

    battery:subscribe({ "routine", "power_source_change", "system_woke" }, function()
        sbar.exec("pmset -g batt", function(info)
            local found, _, charge = info:find("(%d+)%%")
            charge = found and tonumber(charge) or nil
            local charging = info:find("AC Power") ~= nil
            local icon, color = "󰂑", p.good
            if charging then
                icon = "󰂄"
            elseif charge then
                if charge > 80 then icon = "󰁹"
                elseif charge > 60 then icon = "󰂀"
                elseif charge > 40 then icon = "󰁾"
                elseif charge > 20 then icon, color = "󰁻", p.warn
                else icon, color = "󰁺", p.bad end
            end
            battery:set({
                icon = { string = icon, color = color },
                label = { string = charge and (charge .. "%") or "?" },
            })
        end)
    end)

    battery:subscribe("mouse.clicked", function()
        battery:set({ popup = { drawing = "toggle" } })
        sbar.exec("pmset -g batt", function(info)
            local found, _, time = info:find(" (%d+:%d+) remaining")
            remaining:set({ label = found and (time .. "h") or "no estimate" })
        end)
    end)
    battery:subscribe("mouse.exited.global", function()
        battery:set({ popup = { drawing = false } })
    end)
end

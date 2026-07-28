return function(ctx)
    local p, style = ctx.palette, ctx.style
    local popup_script = ctx.helper("volume_popup.sh")

    local volume = sbar.add("item", "widgets.volume", {
        position = "right",
        icon = { string = "󰕾", font = { size = 13.0 } },
        label = { string = "--%", font = { family = ctx.settings.font.numbers } },
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        popup = { align = "center" },
        click_script = popup_script,
    })
    table.insert(ctx.groups.right, volume.name)

    volume:subscribe("volume_change", function(env)
        local vol = tonumber(env.INFO)
        if not vol then return end
        local icon = "󰸈"
        if vol > 60 then icon = "󰕾"
        elseif vol > 30 then icon = "󰖀"
        elseif vol > 0 then icon = "󰕿" end
        volume:set({ icon = { string = icon }, label = { string = vol .. "%" } })
    end)

    volume:subscribe("mouse.scrolled", function(env)
        local delta = env.INFO.delta
        if not (env.INFO.modifier == "ctrl") then delta = delta * 10.0 end
        sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
    end)
end

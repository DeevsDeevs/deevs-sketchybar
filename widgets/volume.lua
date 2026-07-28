return function(ctx)
    local p, style = ctx.palette, ctx.style
    local hex = function(color) return string.format("0x%08x", color) end
    local popup_script = "LABEL_ON=" .. hex(p.fg) .. " LABEL_OFF=" .. hex(ctx.with_alpha(p.fg, 0.45))
        .. " " .. ctx.shell_quote(ctx.helper("volume_popup.sh"))

    local volume = sbar.add("item", "widgets.volume", {
        position = "right",
        icon = { string = "\u{f057e}", font = { size = 13.0 }, color = ctx.with_alpha(p.fg, 0.8) },
        label = { string = "--%", font = { family = ctx.settings.font.numbers }, color = ctx.with_alpha(p.fg, 0.8) },
        icon = { color = ctx.with_alpha(p.fg, 0.8) },
        popup = { align = "center" },
        click_script = popup_script,
    })
    table.insert(ctx.groups.right, volume.name)

    local slider = sbar.add("slider", "widgets.volume.slider", 200, {
        position = "popup." .. volume.name,
        slider = {
            highlight_color = p.accent,
            background = { height = 6, corner_radius = 3, color = ctx.with_alpha(p.fg, 0.15) },
            knob = { string = "\u{f0028}", drawing = true, color = p.accent },
        },
        background = { color = p.transparent },
        click_script = 'osascript -e "set volume output volume $PERCENTAGE"',
    })

    volume:subscribe("volume_change", function(env)
        local vol = tonumber(env.INFO)
        if not vol then return end
        local icon = "\u{f0581}"
        if vol > 60 then icon = "\u{f057e}"
        elseif vol > 30 then icon = "\u{f0580}"
        elseif vol > 0 then icon = "\u{f057f}" end
        volume:set({ icon = { string = icon }, label = { string = vol .. "%" } })
        slider:set({ slider = { percentage = vol } })
    end)

    volume:subscribe("mouse.scrolled", function(env)
        local delta = env.INFO.delta
        if not (env.INFO.modifier == "ctrl") then delta = delta * 10.0 end
        sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
    end)
    volume:subscribe("mouse.exited.global", function()
        volume:set({ popup = { drawing = false } })
        sbar.exec("sketchybar --remove '/volume.device\\..*/' >/dev/null 2>&1")
    end)
end

return function(ctx)
    local p, style = ctx.palette, ctx.style
    local hex = function(color) return string.format("0x%08x", color) end
    local helper = ctx.shell_quote(ctx.helper("audio_devices/bin/audio_devices"))
    local auto_route = (ctx.config.audio or {}).auto_route
    local popup_script = "LABEL_ON=" .. hex(p.fg) .. " LABEL_OFF=" .. hex(ctx.with_alpha(p.fg, 0.45))
        .. (auto_route and " ROUTE_FLAG=--route" or "")
        .. " " .. ctx.shell_quote(ctx.helper("volume_popup.sh"))

    local volume = sbar.add("item", "widgets.volume", {
        position = "right",
        icon = { string = "\u{f057e}", font = { size = 13.0 }, color = ctx.with_alpha(p.fg, 0.8) },
        label = { string = "--%", font = { family = ctx.settings.font.numbers }, color = ctx.with_alpha(p.fg, 0.8) },
        icon = { color = ctx.with_alpha(p.fg, 0.8) },
        popup = { align = "center" },
        update_freq = 5,
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
        click_script = helper .. ' volume $PERCENTAGE',
    })

    local function render(vol)
        if not vol then return end
        local icon = "\u{f0581}"
        if vol > 60 then icon = "\u{f057e}"
        elseif vol > 30 then icon = "\u{f0580}"
        elseif vol > 0 then icon = "\u{f057f}" end
        volume:set({ icon = { string = icon }, label = { string = vol .. "%" } })
        slider:set({ slider = { percentage = vol } })
    end

    -- The routed aggregate has no volume of its own, so the level is read from
    -- the real device; volume_change still fires when nothing is routed.
    local function refresh()
        sbar.exec(helper .. " volume", function(out)
            render(tonumber(tostring(out):match("%d+")))
        end)
    end
    -- A routed aggregate reports 0 to macOS, so trust the helper instead.
    volume:subscribe("volume_change", function(env)
        if auto_route then refresh() else render(tonumber(env.INFO)) end
    end)
    volume:subscribe({ "routine", "forced" }, refresh)
    refresh()

    volume:subscribe("mouse.scrolled", function(env)
        local delta = env.INFO.delta
        if not (env.INFO.modifier == "ctrl") then delta = delta * 10.0 end
        sbar.exec(helper .. " volume " .. (delta > 0 and "+" or "") .. math.floor(delta), refresh)
    end)
    -- Optional: only needed if the media keys do nothing while routed. The
    -- tap consumes the three volume keys and applies them to the real device
    -- beneath the aggregate; everything else passes through.
    if (ctx.config.audio or {}).volume_keys then
        sbar.exec("pkill -f 'helpers/volume_keys/bin/volume_key[s]' >/dev/null 2>&1; "
            .. ctx.detached(ctx.shell_quote(ctx.helper("volume_keys/bin/volume_keys"))))
    end

    volume:subscribe("mouse.exited.global", function()
        volume:set({ popup = { drawing = false } })
        sbar.exec("sketchybar --remove '/volume.device\\..*/' >/dev/null 2>&1")
    end)
end

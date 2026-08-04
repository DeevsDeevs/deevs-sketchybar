return function(ctx)
    ctx.owns_popup()
    local p = ctx.palette
    local hex = function(color) return string.format("0x%08x", color) end
    local helper = ctx.shell_quote(ctx.helper("audio_devices/bin/audio_devices"))
    local auto_route = (ctx.config.audio or {}).auto_route
    local popup_script = string.format("LABEL_ON=%s LABEL_OFF=%s%s %s",
        hex(p.fg), hex(ctx.with_alpha(p.fg, 0.45)),
        auto_route and " ROUTE_FLAG=--route" or "",
        ctx.shell_quote(ctx.helper("volume_popup.sh")))

    -- No click_script: an item with one never forwards mouse events to lua, so mouse.exited.global would never fire.
    local volume = sbar.add("item", "widgets.volume", {
        position = "right",
        icon = { string = "\u{f057e}", font = { size = 13.0 }, color = ctx.with_alpha(p.fg, 0.8) },
        label = { string = "--%", font = { family = ctx.settings.font.numbers }, color = ctx.with_alpha(p.fg, 0.8) },
        popup = { align = "center" },
        update_freq = 5,
    })
    table.insert(ctx.groups.right, volume.name)
    ctx.cluster("status", volume.name)

    local slider = sbar.add("slider", "widgets.volume.slider", 200, {
        position = "popup." .. volume.name,
        slider = {
            highlight_color = p.accent,
            background = { height = 6, corner_radius = 3, color = ctx.with_alpha(p.fg, 0.15) },
            knob = { string = "\u{f0028}", drawing = true, color = p.accent },
        },
        background = { color = p.transparent },
        click_script = string.format("%s volume $PERCENTAGE", helper),
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

    -- The poll only earns its keep while output is routed through the aggregate, which
    -- reports no usable level of its own. On a plain device macOS's own volume_change
    -- is accurate, and asking anyway costs a process that initialises the audio HAL —
    -- about 37ms, every interval, to confirm what the last event already said. The
    -- helper reports which case it is, so the interval follows it.
    local polling = nil
    local function refresh()
        sbar.exec(string.format("%s volume", helper), function(out)
            local reply = tostring(out)
            render(tonumber(reply:match("%d+")))
            local routed = reply:match("routed") ~= nil
            if routed ~= polling then
                polling = routed
                volume:set({ update_freq = routed and 5 or 0 })
            end
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
        sbar.exec(string.format("%s volume %s%d", helper, delta > 0 and "+" or "", math.floor(delta)), refresh)
    end)
    -- Reap and spawn in ONE shell: as two execs the pkill can land after the spawn and kill the tap it was meant to replace.
    local reap = "pkill -x volume_keys >/dev/null 2>&1"
    if (ctx.config.audio or {}).volume_keys then
        sbar.exec(string.format("%s; %s", reap, ctx.detached(ctx.shell_quote(ctx.helper("volume_keys/bin/volume_keys")))))
    else
        sbar.exec(reap)
    end

    -- One message: separate hide + remove renders twice and the popup visibly shrinks before it disappears.
    local function close_popup()
        sbar.exec("sketchybar --set " .. volume.name .. " popup.drawing=off"
            .. " --remove '/volume.device\\..*/' >/dev/null 2>&1")
    end

    volume:subscribe("mouse.clicked", function(env)
        if env.BUTTON == "right" then
            sbar.exec("open /System/Library/PreferencePanes/Sound.prefpane")
            return
        end
        sbar.exec(popup_script)
    end)

    volume:subscribe("mouse.exited.global", close_popup)

    -- Last, after the mouse subscriptions: subscribing an item to mouse events *after*
    -- a custom event silently drops the custom one and it simply never fires.
    -- Picking a device in the popup is the one thing that turns routing on or off, so
    -- this is what lets the poll interval follow it.
    sbar.add("event", "audio_route_changed")
    volume:subscribe("audio_route_changed", refresh)
end

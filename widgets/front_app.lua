return function(ctx)
    local p, c = ctx.palette, ctx.config
    local max_menus = 12

    local front_app = sbar.add("item", "front_app", {
        position = "left",
        display = "active",
        icon = { drawing = false },
        label = {
            font = { family = ctx.settings.font.text, style = "Bold", size = 12.0 },
            color = p.fg,
        },
        updates = true,
    })
    table.insert(ctx.groups.left, front_app.name)

    local system_windows = {
        universalAccessAuthWarn = true,
        loginwindow = true,
        UserNotificationCenter = true,
        CoreServicesUIAgent = true,
    }

    front_app:subscribe("front_app_switched", function(env)
        if system_windows[env.INFO] then return end
        front_app:set({ label = { string = env.INFO } })
    end)

    if not c.menus_swap then return end

    local menus_bin = ctx.helper("menus/bin/menus")
    local swap = ctx.helper("menus_swap.sh")

    for i = 1, max_menus do
        local slot = sbar.add("item", "menu." .. i, {
            position = "left",
            drawing = false,
            updates = true,
            icon = { drawing = false },
            label = {
                font = { family = ctx.settings.font.text, style = "Regular", size = 11.5 },
                color = ctx.with_alpha(p.fg, 0.75),
                padding_left = 6,
                padding_right = 6,
            },
            -- slot i shows the (i+1)th menu: the app menu is the front_app label
            click_script = ctx.shell_quote(menus_bin) .. " -s " .. (i + 1),
        })
        table.insert(ctx.groups.left, slot.name)
    end

    -- Plain click_script: macOS gives the Accessibility grant to the SPAWNING process, which must be sketchybar itself.
    front_app:set({ click_script = "MENU_SLOTS=" .. max_menus .. " " .. ctx.shell_quote(swap) })

    -- CLI-created so its script runs as a real shell script, not through lua.
    sbar.exec("sketchybar --add item menus.refresher left"
        .. " --set menus.refresher drawing=off updates=on"
        -- Quoted twice: sketchybar re-evaluates the script= string as shell.
        .. " script=" .. ctx.shell_quote("MENU_SLOTS=" .. max_menus .. " "
            .. ctx.shell_quote(swap) .. " refresh")
        .. " --subscribe menus.refresher front_app_switched")

    sbar.exec(ctx.shell_quote(swap) .. " hide")
end

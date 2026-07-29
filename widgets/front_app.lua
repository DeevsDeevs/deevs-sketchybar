-- Front app name; when menus_swap is on, clicking it swaps spaces ↔ app menus.
--
-- The swap itself lives in helpers/menus_swap.sh and is invoked as a plain
-- click_script/script: sketchybar has to be the process that spawns the
-- accessibility-backed `menus` helper, otherwise it returns nothing.
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

    -- System dialogs surface as internal window names (the accessibility
    -- prompt is "universalAccessAuthWarn"); keep showing the last real app.
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
        sbar.add("item", "menu." .. i, {
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
    end

    front_app:set({ click_script = "MENU_SLOTS=" .. max_menus .. " " .. ctx.shell_quote(swap) })

    -- Shell-side refresher: created through the CLI so its script stays a real
    -- shell script (a lua subscription would route it back through lua).
    sbar.exec("sketchybar --add item menus.refresher left"
        .. " --set menus.refresher drawing=off updates=on"
        .. " script=" .. ctx.shell_quote("MENU_SLOTS=" .. max_menus .. " " .. swap .. " refresh")
        .. " --subscribe menus.refresher front_app_switched")

    -- Always start in spaces mode after a reload.
    sbar.exec(ctx.shell_quote(swap) .. " hide")
end

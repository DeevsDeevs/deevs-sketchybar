-- Front app name; when menus_swap is on, clicking it swaps spaces ↔ app menus.
-- Mode lives in this variable — never derived from item state (that desyncs).
return function(ctx)
    local p, c = ctx.palette, ctx.config
    local menu_mode = false
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

    front_app:subscribe("front_app_switched", function(env)
        front_app:set({ label = { string = env.INFO } })
        if menu_mode then sbar.trigger("menus_refresh") end
    end)

    if not c.menus_swap then return end

    local menus_bin = ctx.helper("menus/bin/menus")
    local menu_items = {}
    for i = 1, max_menus do
        local menu = sbar.add("item", "menu." .. i, {
            position = "left",
            drawing = false,
            icon = { drawing = false },
            label = {
                font = { family = ctx.settings.font.text, style = i == 1 and "Bold" or "Regular", size = 11.5 },
                color = i == 1 and p.accent or ctx.with_alpha(p.fg, 0.75),
                padding_left = 6,
                padding_right = 6,
            },
            click_script = menus_bin .. " -s " .. i,
        })
        menu_items[i] = menu
    end

    sbar.add("event", "menus_refresh")
    local refresher = sbar.add("item", { drawing = false, updates = true })

    local function update_menus()
        sbar.exec(ctx.shell_quote(menus_bin) .. " -l", function(menus)
            local id = 1
            for menu in string.gmatch(menus, "[^\r\n]+") do
                if id > max_menus then break end
                menu_items[id]:set({ label = menu, drawing = true })
                id = id + 1
            end
            for i = id, max_menus do menu_items[i]:set({ drawing = false }) end
        end)
    end

    local function set_mode(mode)
        menu_mode = mode
        sbar.set("/space\\..*/", { drawing = not mode })
        front_app:set({ label = { color = mode and p.accent or p.fg } })
        if mode then
            update_menus()
        else
            for i = 1, max_menus do menu_items[i]:set({ drawing = false }) end
        end
    end

    refresher:subscribe("menus_refresh", function() update_menus() end)
    front_app:subscribe("mouse.clicked", function() set_mode(not menu_mode) end)
end

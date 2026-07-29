local app_icons = require("helpers.app_icons")

return function(ctx)
    local p, c, style = ctx.palette, ctx.config, ctx.style
    local spaces = {}

    local max = (type(c.spaces) == "table" and c.spaces.max) or 10

    local function active_space_indices()
        local handle = io.popen("yabai -m query --spaces 2>/dev/null")
        local output = handle and handle:read("*a") or ""
        if handle then handle:close() end
        local indices, seen = {}, {}
        for index in output:gmatch('"index"%s*:%s*(%d+)') do
            local n = tonumber(index)
            if n and not seen[n] then
                table.insert(indices, n)
                seen[n] = true
            end
        end
        table.sort(indices)
        if #indices == 0 then
            for i = 1, max do table.insert(indices, i) end
        end
        -- max is documented as a cap, so honour it for the yabai answer too;
        -- it used to apply only to the no-yabai fallback and silently did
        -- nothing on a working setup.
        while #indices > max do table.remove(indices) end
        return indices
    end

    for _, i in ipairs(active_space_indices()) do
        local ramp = p.mood or {}
        local accent = (c.mood and #ramp > 0) and ramp[((i - 1) % #ramp) + 1] or ctx.with_alpha(p.fg, 0.18)
        local hi = (c.mood and #ramp > 0) and p.ink or p.fg
        local space = sbar.add("space", "space." .. i, {
            space = i,
            padding_left = 3,
            padding_right = 3,
            icon = {
                string = i,
                font = { family = ctx.settings.font.numbers },
                color = ctx.with_alpha(p.fg, 0.55),
                highlight_color = p.ink,
                padding_left = 10,
                padding_right = c.spaces.icons and 4 or 10,
            },
            label = {
                drawing = c.spaces.icons,
                font = ctx.settings.font.app_icons,
                color = ctx.with_alpha(p.fg, 0.5),
                highlight_color = p.ink,
                padding_left = 0,
                padding_right = 10,
                y_offset = -1,
            },
            background = { color = p.transparent, height = style.item_height, corner_radius = style.item_radius },
        })
        spaces[i] = { item = space, accent = accent }

        space:subscribe("space_change", function(env)
            local selected = env.SELECTED == "true"
            space:set({
                icon = { highlight = selected },
                label = { highlight = selected },
                background = { color = selected and accent or p.transparent },
            })
        end)

        space:subscribe("mouse.clicked", function(env)
            sbar.exec("yabai -m space --focus " .. env.SID)
        end)
    end

    local observer = sbar.add("item", { drawing = false, updates = true })
    observer:subscribe("space_windows_change", function(env)
        local icon_line = ""
        local no_app = true
        for app in pairs(env.INFO.apps) do
            no_app = false
            icon_line = icon_line .. (app_icons[app] or app_icons["Default"])
        end
        if no_app then icon_line = "—" end
        -- Spaces created after startup have no item yet; they appear on reload.
        local entry = spaces[tonumber(env.INFO.space)]
        if entry then entry.item:set({ label = icon_line }) end
    end)

    for i, entry in pairs(spaces) do
        table.insert(ctx.groups.left, entry.item.name)
    end
end

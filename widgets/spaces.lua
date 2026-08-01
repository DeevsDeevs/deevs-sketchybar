local app_icons = require("helpers.app_icons")

return function(ctx)
    local p, c, style = ctx.palette, ctx.config, ctx.style
    local spaces = {}

    -- `spaces = true` is documented shorthand: indexing a boolean would kill the whole bar.
    local conf = type(c.spaces) == "table" and c.spaces or {}
    local max = conf.max or 20
    local show_icons = conf.icons ~= false

    -- A pool, not a snapshot. sketchybar resolves each space item to the display owning
    -- that mission control index and redraws when spaces are created or destroyed;
    -- an item for a space that does not exist gets a sentinel display mask and stays
    -- hidden. So spaces appear on the right bar with no rebuild and no yabai signal.
    for i = 1, max do
        local ramp = p.mood or {}
        local accent = (c.mood and #ramp > 0) and ramp[((i - 1) % #ramp) + 1] or ctx.with_alpha(p.fg, 0.18)
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
                padding_right = show_icons and 4 or 10,
            },
            label = {
                drawing = show_icons,
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
        local entry = spaces[tonumber(env.INFO.space)]
        if entry then entry.item:set({ label = icon_line }) end
    end)

    for i, entry in pairs(spaces) do
        table.insert(ctx.groups.left, entry.item.name)
    end
end

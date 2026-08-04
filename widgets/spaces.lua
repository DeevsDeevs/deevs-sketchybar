local app_icons = require("helpers.app_icons")

return function(ctx)
    local p, c, style = ctx.palette, ctx.config, ctx.style
    local spaces = {}

    -- `spaces = true` is documented shorthand: indexing a boolean would kill the whole bar.
    local conf = type(c.spaces) == "table" and c.spaces or {}
    local max = conf.max or 20
    local show_icons = conf.icons ~= false

    -- Unconditional on purpose: skipping the repaints that look redundant measured no
    -- cheaper, and caching what each item looks like goes stale when sketchybar
    -- re-associates them across a space being created or destroyed.
    local function highlight(index, selected)
        local entry = spaces[index]
        if not entry then return end
        entry.item:set({
            icon = { highlight = selected },
            label = { highlight = selected },
            background = { color = selected and entry.accent or p.transparent },
        })
    end

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
            highlight(i, env.SELECTED == "true")
        end)

        -- string.format, never `..`: concatenation can drop an operand and build a
        -- `--focus` with no argument.
        space:subscribe("mouse.clicked", function(env)
            sbar.exec(string.format("yabai -m space --focus %s", env.SID))
        end)
    end

    local observer = sbar.add("item", { drawing = false, updates = true })
    -- One trigger fans out to a call per space, so a single window opening sweeps them all.
    observer:subscribe("space_windows_change", function(env)
        local entry = spaces[tonumber(env.INFO.space)]
        if not entry then return end

        -- Sorted because `pairs` order is not stable: the same apps can hash differently
        -- next time, which visibly reshuffles the icons and defeats the check below.
        local names = {}
        for app in pairs(env.INFO.apps) do names[#names + 1] = app end
        table.sort(names)

        local icons = {}
        for i, app in ipairs(names) do icons[i] = app_icons[app] or app_icons["Default"] end
        local icon_line = #icons > 0 and table.concat(icons) or "—"

        if entry.icon_line == icon_line then return end
        entry.icon_line = icon_line
        entry.item:set({ label = icon_line })
    end)

    -- space_change is only sent when a space actually changes, so nothing looks selected
    -- after a reload, and plugging a display in can strand a chip lit for a space that is
    -- no longer visible. Every space is written, not just the visible ones: lighting the
    -- right chip is useless if the stale one stays lit beside it.
    local function resync()
        sbar.exec("yabai -m query --spaces 2>/dev/null", function(result)
            if type(result) ~= "table" then return end
            local visible = {}
            for _, space in ipairs(result) do
                if space["is-visible"] then visible[tonumber(space.index)] = true end
            end
            for index in pairs(spaces) do highlight(index, visible[index] == true) end
        end)
    end
    resync()
    observer:subscribe("display_change", resync)

    for _, entry in pairs(spaces) do
        table.insert(ctx.groups.left, entry.item.name)
    end
end

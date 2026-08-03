local app_icons = require("helpers.app_icons")

return function(ctx)
    local p, c, style = ctx.palette, ctx.config, ctx.style
    local spaces = {}

    -- `spaces = true` is documented shorthand: indexing a boolean would kill the whole bar.
    local conf = type(c.spaces) == "table" and c.spaces or {}
    local max = conf.max or 20
    local show_icons = conf.icons ~= false

    -- Repainting an item that already looks right still costs a message, and a space
    -- change is delivered to every space item, so the redundant ones are dropped here.
    local function highlight(index, selected)
        local entry = spaces[index]
        if not entry or entry.selected == selected then return end
        entry.selected = selected
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
        -- Seeded to match how the item was just built, so the sweep of space_change
        -- events at startup only touches the one space that is actually selected.
        spaces[i] = { item = space, accent = accent, selected = false }

        -- Every space item hears every space change, so a switch used to redraw all of
        -- them when only two ever differ: the one being left and the one being entered.
        space:subscribe("space_change", function(env)
            highlight(i, env.SELECTED == "true")
        end)

        -- string.format, never `..`: concatenation can drop an operand here and build a
        -- `yabai -m space --focus` with no argument.
        space:subscribe("mouse.clicked", function(env)
            sbar.exec(string.format("yabai -m space --focus %s", env.SID))
        end)
    end

    local observer = sbar.add("item", { drawing = false, updates = true })
    -- One trigger fans out to a call per space, so a single window opening costs a full
    -- sweep of them. Both halves of that are answered here: the icons are built into a
    -- stable string, and an unchanged one is dropped before it becomes a message.
    observer:subscribe("space_windows_change", function(env)
        local entry = spaces[tonumber(env.INFO.space)]
        if not entry then return end

        -- Sorted, because `pairs` order is not stable: the same set of apps could hash
        -- into a different order on the next event, which both shuffles the icons on
        -- screen and defeats the comparison below.
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

    -- Nothing looks selected after a reload: space_change is only sent when a space
    -- actually changes, and `--trigger space_change` carries no SELECTED to act on. So
    -- ask yabai once for the space each display is showing and light those.
    sbar.exec("yabai -m query --spaces 2>/dev/null", function(result)
        if type(result) ~= "table" then return end
        for _, space in ipairs(result) do
            if space["is-visible"] then highlight(tonumber(space.index), true) end
        end
    end)

    for i, entry in pairs(spaces) do
        table.insert(ctx.groups.left, entry.item.name)
    end
end

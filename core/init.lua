sbar = require("sketchybar")

local config = require("config")
local palette = require("palettes." .. config.palette)

local ctx = {
    config = config,
    palette = palette,
    settings = require("core.settings"),
    config_dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar"),
    groups = { left = {}, center = {}, right = {} },
    clusters = {},   -- name -> item names sharing one chip
}

function ctx.with_alpha(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
end

function ctx.helper(name)
    return ctx.config_dir .. "/helpers/" .. name
end

-- Detach long-running helpers from sketchybar's fds so reloads don't orphan them.
function ctx.detached(command)
    return "( for fd in $(jot 253 3); do eval \"exec ${fd}>&-\" 2>/dev/null || true; done; exec </dev/null >/dev/null 2>&1 " .. command .. " ) &"
end

function ctx.shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- The rounded slab behind a cluster of items. Every widget draws its
-- background through this so the bar keeps one rhythm instead of some chips
-- having a slab and some floating bare; `chips = false` drops them all.
-- Returns a stub rather than nil when off, so callers can still :set() it.
local no_chip = { set = function() end }

-- Join a shared chip instead of claiming your own. The small status widgets
-- use this so they land under one slab rather than a row of separate pills.
function ctx.cluster(name, item)
    ctx.clusters[name] = ctx.clusters[name] or {}
    table.insert(ctx.clusters[name], item)
end

-- Blank fixed-width item used to separate chips. A bracket's own padding grows
-- its extent by the same amount it insets the background, so the slab always
-- ends up hugging its contents and neighbouring chips touch no matter what is
-- set on them. An item that belongs to neither bracket is the only thing that
-- reliably keeps them apart.
local gaps = 0

function ctx.gap(width)
    if ctx.config.chips == false then return end
    gaps = gaps + 1
    local item = sbar.add("item", "gap." .. gaps, {
        position = "right",
        width = width or 10,
        padding_left = 0,
        padding_right = 0,
        icon = { drawing = false },
        label = { drawing = false },
        background = { drawing = false },
    })
    -- Joins the group so the islands structure includes it in the pod; left out,
    -- the pod is built around the spacer rather than across it.
    table.insert(ctx.groups.right, item.name)
    return item.name
end

-- Drop a spacer again. Whether a widget draws at all is only known after it has
-- run, and its spacer has to exist before it to land on the right side of it, so
-- the loader speculates and hands the name back when nothing appeared.
function ctx.ungap(name)
    if not name then return end
    for i = #ctx.groups.right, 1, -1 do
        if ctx.groups.right[i] == name then table.remove(ctx.groups.right, i) break end
    end
    sbar.remove(name)
end

function ctx.chip(name, members, opts)
    -- A memberless bracket is rejected by sketchybar, and every later :set on it
    -- then addresses an item that does not exist.
    if ctx.config.chips == false or not members or #members == 0 then return no_chip end
    local props = {
        background = {
            color = ctx.style.item_bg,
            corner_radius = ctx.style.item_radius,
            height = ctx.style.item_height,
        },
    }
    for key, value in pairs(opts or {}) do props[key] = value end
    return sbar.add("bracket", name, members, props)
end

-- Normalise the optional blocks once, here, rather than guarding every read:
-- the structures run before any widget exists, so an omitted `bar` block took
-- the whole bar down with it instead of just losing a feature.
config.bar = type(config.bar) == "table" and config.bar or {}
config.bar.height = config.bar.height or 40

local structure = require("structures." .. config.structure)
ctx.style = structure.style(ctx)

sbar.begin_config()
structure.apply(ctx)
require("widgets.init").load(ctx)
for name, members in pairs(ctx.clusters) do ctx.chip(name .. ".chip", members) end
if structure.finish then structure.finish(ctx) end
sbar.end_config()

sbar.event_loop()

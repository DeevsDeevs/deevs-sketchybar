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

function ctx.chip(name, members, opts)
    if ctx.config.chips == false then return no_chip end
    local props = {
        background = {
            color = ctx.style.item_bg,
            corner_radius = ctx.style.item_radius,
            height = ctx.style.item_height,
            -- A bracket hugs its members exactly, so neighbouring chips end up
            -- edge to edge and read as one long slab with seams. Inset the
            -- drawn background to put real air between them.
            padding_left = 5,
            padding_right = 5,
        },
    }
    for key, value in pairs(opts or {}) do props[key] = value end
    return sbar.add("bracket", name, members, props)
end

local structure = require("structures." .. config.structure)
ctx.style = structure.style(ctx)

sbar.begin_config()
structure.apply(ctx)
require("widgets.init").load(ctx)
for name, members in pairs(ctx.clusters) do ctx.chip(name .. ".chip", members) end
if structure.finish then structure.finish(ctx) end
sbar.end_config()

sbar.event_loop()

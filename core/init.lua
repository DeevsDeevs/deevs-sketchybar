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

-- string.format, never concatenation: it can drop an operand here (bare '' for
-- a 60-char path). The extra parens keep gsub's second return out of format.
function ctx.shell_quote(value)
    return string.format("'%s'", (tostring(value):gsub("'", "'\\''")))
end

-- Coordinates as an Open-Meteo query fragment, or nil if Location Services
-- said no. Cached for the session; two widgets ask.
local located
function ctx.locate(done)
    if located then return done(located) end
    sbar.exec(ctx.shell_quote(
        ctx.helper("location/bin/location.app/Contents/MacOS/location")), function(out)
        local lat, lon = tostring(out):match("(-?%d+%.?%d*)%s+(-?%d+%.?%d*)")
        if not lat then return done(nil) end
        located = string.format("latitude=%s&longitude=%s", lat, lon)
        done(located)
    end)
end

-- Rounded slab behind a cluster of items. With chips = false, ctx.chip returns
-- this stub rather than nil so callers can still :set() it.
local no_chip = { set = function() end }

-- Join a shared chip instead of claiming your own.
function ctx.cluster(name, item)
    ctx.clusters[name] = ctx.clusters[name] or {}
    table.insert(ctx.clusters[name], item)
end

-- Blank spacer between chips: a bracket's padding IS its background inset, so
-- a bracket can never be inset from its own contents — only a foreign item separates them.
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
    -- In the group so the islands pod spans the spacer.
    table.insert(ctx.groups.right, item.name)
    return item.name
end

-- Drop a spacer the loader created speculatively for a widget that drew nothing.
function ctx.ungap(name)
    if not name then return end
    for i = #ctx.groups.right, 1, -1 do
        if ctx.groups.right[i] == name then table.remove(ctx.groups.right, i) break end
    end
    sbar.remove(name)
end

function ctx.chip(name, members, opts)
    -- sketchybar rejects a memberless bracket.
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

-- Normalise optional blocks before the structures read them; a missing `bar`
-- block must not take the whole bar down.
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

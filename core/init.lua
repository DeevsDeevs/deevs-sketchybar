sbar = require("sketchybar")

local config = require("config")
local palette = require("palettes." .. config.palette)

local ctx = {
    config = config,
    palette = palette,
    settings = require("core.settings"),
    config_dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar"),
    groups = { left = {}, center = {}, right = {} },
    clusters = {},
}

local follows_active, active_items = {}, {}
local on_active = { associated_display = "active" }

-- Declared by every widget that owns a popup. Sketchybar gives an item a single
-- popup window with a single anchor, and every bar rewrites that anchor while it is
-- open, so with two bars the dropdown lands on whichever redrew last — the wrong
-- display, in that bar's coordinates. `display = active` leaves exactly one bar
-- laying the widget out, so the popup opens where you are working.
--
-- The whole widget follows, not only the item holding the popup: session is
-- icon+time+name and media is cover+artist+title, and moving one part alone leaves
-- a chip with a hole in it. Its popup rows have to come too, or the popup opens
-- empty. Widgets without a popup stay on every display.
--
-- Declared rather than detected from the "popup.<host>" rows: herdr builds its rows
-- inside its click handler, so there is nothing to detect until the popup is already
-- opening. Marking the widget instead catches every item it ever adds.
function ctx.owns_popup()
    if ctx.current_widget then follows_active[ctx.current_widget] = true end
end

local raw_add = sbar.add
function sbar.add(...)
    local item = raw_add(...)
    -- `sbar.add("event", name)` hands back a name too, and setting a property on an
    -- event just logs "Item not found" on every display switch.
    if (...) ~= "event" and follows_active[ctx.current_widget]
        and type(item) == "table" and item.name then
        active_items[item.name] = true
        sbar.set(item.name, on_active)
    end
    return item
end

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

-- Concatenation can drop an operand here — string.format only; parens strip gsub's second return.
function ctx.shell_quote(value)
    return string.format("'%s'", (tostring(value):gsub("'", "'\\''")))
end

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

-- Returns the fixed alias (nil = local) and whether the widget tracks the picker.
function ctx.host_of(conf)
    local host = type(conf) == "table" and conf.host or "local"
    if host == "selected" then return nil, true end
    if host == "local" or type(host) ~= "string" then return nil, false end
    return host, false
end

local no_chip = { set = function() end }

function ctx.cluster(name, item)
    ctx.clusters[name] = ctx.clusters[name] or {}
    table.insert(ctx.clusters[name], item)
end

-- A bracket's padding IS its background inset, so separating chips needs blank spacer items.
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
    table.insert(ctx.groups.right, item.name)
    return item.name
end

function ctx.ungap(name)
    if not name then return end
    for i = #ctx.groups.right, 1, -1 do
        if ctx.groups.right[i] == name then table.remove(ctx.groups.right, i) break end
    end
    sbar.remove(name)
end

function ctx.chip(name, members, opts)
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

config.bar = type(config.bar) == "table" and config.bar or {}
config.bar.height = config.bar.height or 40

local structure = require("structures." .. config.structure)
ctx.style = structure.style(ctx)

sbar.begin_config()
structure.apply(ctx)
require("widgets.init").load(ctx)
for name, members in pairs(ctx.clusters) do
    local chip = ctx.chip(name .. ".chip", members)
    -- A cluster bracket belongs to no widget, so it follows its members: it travels
    -- only when all of them do, and otherwise stays put to frame what is left.
    local all = #members > 0
    for _, member in ipairs(members) do all = all and active_items[member] end
    if all then chip:set(on_active) end
end
-- A popup belongs to the bar that opened it. Move focus to another display and the
-- widget follows, leaving the popup behind as an empty frame nothing can close —
-- the item it hangs off is no longer on that bar to receive the click or the exit.
-- display_change fires whenever the active display changes, so shut them there.
--
-- Set through the API, never by shelling out to the sketchybar CLI: invoked from
-- inside the config process it finds the running instance's lock file and exits with
-- "could not acquire lock-file" instead of delivering the message.
local popup_watch = sbar.add("item", { drawing = false, updates = true })
popup_watch:subscribe("display_change", function()
    for name in pairs(active_items) do
        sbar.set(name, { popup = { drawing = false } })
    end
end)

if structure.finish then structure.finish(ctx) end
sbar.end_config()

sbar.event_loop()

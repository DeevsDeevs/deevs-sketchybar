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

local has_popup, owner_of, items_of = {}, {}, {}
local held = nil

-- Sketchybar gives an item a single popup window with a single anchor, and every bar
-- rewrites that anchor while the popup is open, so with two bars the dropdown lands
-- on whichever redrew last — the wrong display, in that bar's coordinates. Nothing in
-- the click path records which bar was clicked, so it cannot simply follow the mouse.
--
-- Widgets therefore stay on every display, and only while a popup is open is its
-- widget held to the display the pointer is on, leaving one bar to lay it out. The
-- whole widget is held, popup rows included: holding only the item that owns the
-- popup leaves a chip with a hole in it, and leaving the rows behind opens it empty.
--
-- Declared rather than detected from the "popup.<host>" rows: herdr builds its rows
-- inside its click handler, so there is nothing to detect until the popup is already
-- opening. Marking the widget instead catches every item it ever adds.
function ctx.owns_popup()
    if ctx.current_widget then has_popup[ctx.current_widget] = true end
end

local raw_add = sbar.add
function sbar.add(...)
    local item = raw_add(...)
    local owner = ctx.current_widget
    if has_popup[owner] and type(item) == "table" and type(item.name) == "string" then
        owner_of[item.name] = owner
        items_of[owner] = items_of[owner] or {}
        table.insert(items_of[owner], item.name)
    end
    return item
end

-- "" clears the association, putting the widget back on every bar. Not "all", which
-- is valid for the bar but not for an item: it parses as 1 << strtoul("all") — a mask
-- for display zero — and silently hides whatever it is set on.
local function hold(widget, display)
    for _, name in ipairs(items_of[widget] or {}) do
        sbar.set(name, { associated_display = display })
    end
end

local function release()
    if held then hold(held, "") end
    held = nil
end

-- Held to the active display, not to the pointer's: a popup only ever renders on the
-- active display. Holding one to the display under the mouse draws nothing at all
-- when you are working elsewhere — the popup opens, reports drawing=on, and never
-- appears on either bar.
function ctx.popup_held(item)
    local widget = owner_of[item.name]
    if held and held ~= widget then release() end
    held = widget
    hold(widget, "active")
end

-- `build` runs with the widget marked, so any row it creates now is held with the
-- rest of it.
function ctx.popup_open(item, build)
    if build then
        ctx.current_widget = owner_of[item.name]
        build()
        ctx.current_widget = nil
    end
    ctx.popup_held(item)
    item:set({ popup = { drawing = "toggle" } })
end

-- A cluster bracket is built after every widget has loaded, so it has no owner of its
-- own; it takes the owner its members share, and only if they all share one.
function ctx.adopt_chip(chip, members)
    if #members == 0 then return end
    local widget = owner_of[members[1]]
    if not widget then return end
    for _, member in ipairs(members) do
        if owner_of[member] ~= widget then return end
    end
    owner_of[chip] = widget
    table.insert(items_of[widget], chip)
end

function ctx.popup_close(item)
    item:set({ popup = { drawing = false } })
    ctx.popup_released(item)
end

-- For widgets that open or close their popup by shell rather than through the Lua
-- item, so the hold is dropped even though nothing was set from here.
function ctx.popup_released(item)
    if held == owner_of[item.name] then release() end
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
    ctx.chip(name .. ".chip", members)
    -- A cluster bracket belongs to no widget, so it joins one only when every member
    -- does; otherwise it stays to frame the members that are not going anywhere.
    ctx.adopt_chip(name .. ".chip", members)
end
if structure.finish then structure.finish(ctx) end
sbar.end_config()

sbar.event_loop()

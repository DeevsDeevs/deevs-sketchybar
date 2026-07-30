local M = {}

-- `widget = true` / `widget = false` is as valid as a table: config.lua teaches
-- the shorthand for mood and menus_swap, so accept it everywhere. Testing the
-- type first matters — indexing .enabled on a boolean throws during config
-- load, which takes down every widget after it and leaves a half-built bar.
local function on(feature)
    if type(feature) ~= "table" then return feature == true end
    return feature.enabled ~= false
end

function M.load(ctx)
    local c = ctx.config

    -- left
    require("widgets.brand")(ctx)
    if on(c.spaces) then require("widgets.spaces")(ctx) end
    require("widgets.front_app")(ctx) -- carries the menus swap when enabled

    -- right (added rightmost-first). Each cluster is separated by a spacer, but
    -- only once something has actually been drawn on both sides of it —
    -- unconditional gaps left dead whitespace where a disabled widget used to be.
    -- `enabled` is not enough to go by: a widget whose dependency is missing
    -- returns without adding anything, so ask the group whether it grew.
    local drawn = false
    local function add(names)
        local before = #ctx.groups.right
        for _, name in ipairs(names) do
            if on(c[name]) then require("widgets." .. name)(ctx) end
        end
        return #ctx.groups.right > before
    end

    local function cluster(names)
        local spacer = drawn and ctx.gap() or nil
        if add(names) then
            drawn = true
        else
            -- Nothing landed after all; take the spacer back out rather than
            -- leaving a hole where the widget would have been.
            ctx.ungap(spacer)
        end
    end

    -- The small status chips share one bracket, so they go in as one cluster with
    -- no spacers between them.
    drawn = add({ "calendar", "battery", "volume", "mic", "vpn", "lang", "weather" })

    cluster({ "surf" })
    cluster({ "session" })
    cluster({ "herdr" })
    cluster({ "repo" })
    cluster({ "servers" })
    cluster({ "system" })
    cluster({ "media" })
end

return M

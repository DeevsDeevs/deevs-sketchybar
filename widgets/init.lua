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
    local drawn = false
    local function cluster(enabled, name)
        if not enabled then return end
        if drawn then ctx.gap() end
        require("widgets." .. name)(ctx)
        drawn = true
    end

    -- The small status chips share one chip, so they are one cluster: no spacer
    -- between them.
    local status = false
    for _, w in ipairs({ "calendar", "battery", "volume", "mic", "vpn" }) do
        if on(c[w]) then
            require("widgets." .. w)(ctx)
            status = true
        end
    end
    drawn = status

    cluster(on(c.session), "session")
    cluster(on(c.herdr), "herdr")
    cluster(on(c.system), "system")
    cluster(on(c.media), "media")
end

return M

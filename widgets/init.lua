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

    -- right (added rightmost-first)
    if on(c.calendar) then require("widgets.calendar")(ctx) end
    if on(c.battery) then require("widgets.battery")(ctx) end
    if on(c.volume) then require("widgets.volume")(ctx) end
    if on(c.mic) then require("widgets.mic")(ctx) end
    if on(c.vpn) then require("widgets.vpn")(ctx) end
    if on(c.session) then require("widgets.session")(ctx) end
    if on(c.herd) then require("widgets.herd")(ctx) end
    if on(c.system) then require("widgets.system")(ctx) end
    if on(c.media) then require("widgets.media")(ctx) end
end

return M

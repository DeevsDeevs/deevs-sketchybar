local M = {}

-- Type first: `widget = true` is valid config, and indexing .enabled on a boolean
-- throws, taking down every widget after it.
local function on(feature)
    if type(feature) ~= "table" then return feature == true end
    return feature.enabled ~= false
end

function M.load(ctx)
    local c = ctx.config

    require("widgets.brand")(ctx)
    if on(c.spaces) then require("widgets.spaces")(ctx) end
    require("widgets.front_app")(ctx)

    -- media with side = "left" belongs to this group, so it must not also be given a
    -- right-hand spacer below.
    local media_left = on(c.media) and type(c.media) == "table" and c.media.side == "left"
    if media_left then require("widgets.media")(ctx) end

    -- Right-position items lay out RIGHT-TO-LEFT in creation order.
    local drawn = false
    local function add(names)
        local before = #ctx.groups.right
        for _, name in ipairs(names) do
            if on(c[name]) then require("widgets." .. name)(ctx) end
        end
        return #ctx.groups.right > before
    end

    -- Spacer only where a cluster actually grew the group: `enabled` can't tell, since a
    -- widget whose dependency is missing adds nothing and would leave a dangling gap.
    local function cluster(names)
        local spacer = drawn and ctx.gap() or nil
        if add(names) then
            drawn = true
        else
            ctx.ungap(spacer)
        end
    end

    drawn = add({ "calendar", "battery", "volume", "mic", "vpn", "lang", "weather" })

    cluster({ "surf" })
    cluster({ "session" })
    cluster({ "repo" })
    -- One unit: the selector sits between the two widgets it retargets.
    cluster({ "herdr", "servers", "system" })
    if not media_left then cluster({ "media" }) end
end

return M

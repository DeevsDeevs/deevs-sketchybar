local M = {}

-- Accept `widget = true/false` as well as a table; check the type first —
-- indexing .enabled on a boolean throws and takes down every widget after it.
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

    -- right (lays out right-to-left in creation order). Spacers only between clusters
    -- that actually grew the group; `enabled` alone can't tell (missing dependency).
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
            ctx.ungap(spacer)
        end
    end

    -- Status chips share one bracket: one cluster, no spacers between.
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

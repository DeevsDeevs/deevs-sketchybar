local M = {}

-- Type first: `widget = true` is valid config, and indexing .enabled on a boolean
-- throws, taking down every widget after it.
local function on(feature)
    if type(feature) ~= "table" then return feature == true end
    return feature.enabled ~= false
end

function M.load(ctx)
    local c = ctx.config

    -- Names every item a widget creates, so `ctx.owns_popup` can move the whole widget
    -- rather than the single item that happens to own the popup.
    local function load(name)
        ctx.current_widget = name
        require("widgets." .. name)(ctx)
        ctx.current_widget = nil
    end

    load("brand")
    if on(c.spaces) then load("spaces") end
    load("front_app")

    -- media with side = "left" belongs to this group, so it must not also be given a
    -- right-hand spacer below.
    local media_left = on(c.media) and type(c.media) == "table" and c.media.side == "left"
    if media_left then load("media") end

    -- Right-position items lay out RIGHT-TO-LEFT in creation order.
    local drawn = false
    -- `sep` separates widgets *inside* one cluster: without it their chips share an edge
    -- and read as one smeared pill, with the full gap they stop looking related.
    local function add(names, sep)
        local before = #ctx.groups.right
        local drew = false
        for _, name in ipairs(names) do
            if on(c[name]) then
                local spacer = (drew and sep) and ctx.gap(sep) or nil
                local mark = #ctx.groups.right
                load(name)
                if #ctx.groups.right > mark then drew = true else ctx.ungap(spacer) end
            end
        end
        return #ctx.groups.right > before
    end

    -- Spacer only where a cluster actually grew the group: `enabled` can't tell, since a
    -- widget whose dependency is missing adds nothing and would leave a dangling gap.
    local function cluster(names, sep)
        local spacer = drawn and ctx.gap() or nil
        if add(names, sep) then
            drawn = true
        else
            ctx.ungap(spacer)
        end
    end

    drawn = add({ "calendar", "battery", "caffeine", "volume", "mic", "vpn", "lang", "weather" })

    cluster({ "surf" })
    cluster({ "session" })
    cluster({ "repo" })
    -- One unit: the selector sits between the two widgets it retargets.
    cluster({ "herdr", "servers", "system" }, 5)
    if not media_left then cluster({ "media" }) end
end

return M

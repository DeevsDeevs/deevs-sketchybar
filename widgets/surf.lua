return function(ctx)
    local p = ctx.palette
    local cfg = ctx.config.surf or {}
    -- A break is a point in the water, so this takes coordinates rather than a
    -- place name: geocoding "Carcavelos" lands in the town, where the marine
    -- model has no data and every field comes back null.
    local lat, lon = tonumber(cfg.lat), tonumber(cfg.lon)
    if not (lat and lon) then return end
    local up = tonumber(cfg.up) or 1.5
    local dim = ctx.with_alpha(p.fg, 0.7)

    local surf = sbar.add("item", "widgets.surf", {
        position = "right",
        icon = { string = "\u{f078d}", font = { size = 13.0 }, color = dim },
        label = { string = "--", font = { family = ctx.settings.font.numbers }, color = dim },
        update_freq = 1800,
    })
    table.insert(ctx.groups.right, surf.name)
    ctx.cluster("surf", surf.name)

    -- Not tostring/concat: lua_Number formatting is locale-sensitive (38.68
    -- becomes "38,68" under a comma-decimal locale) and tiny values go
    -- scientific ("1e-05"); either corrupts the query string.
    local function coord(n) return (string.format("%.4f", n):gsub(",", ".")) end
    local url = "https://marine-api.open-meteo.com/v1/marine?latitude=" .. coord(lat)
        .. "&longitude=" .. coord(lon) .. "&current=wave_height,wave_period"

    local function fetch()
        sbar.exec("curl -s --max-time 8 " .. ctx.shell_quote(url), function(out)
            -- SbarLua parses JSON stdout into a table before the callback; a
            -- non-table (empty or garbage body) is a transport failure, so
            -- keep the last reading through the blip.
            if type(out) ~= "table" then return end
            -- JSON null fields arrive as absent keys (the bridge pushes nil,
            -- which lua_settable drops), and an API error object has no
            -- .current at all — both mean answered-but-no-data (inland or
            -- off the marine grid): degrade visibly, never keep stale surf.
            local cur = type(out.current) == "table" and out.current or {}
            local height = tonumber(cur.wave_height)
            if not height then
                surf:set({ icon = { color = dim }, label = { string = "--", color = dim } })
                return
            end
            -- Threshold compares the rounded display value so "1.5m" never
            -- sits unlit next to up = 1.5.
            local shown = math.floor(height * 10 + 0.5) / 10
            local firing = shown >= up
            -- current_units is echoed back by the API, so the suffix tracks
            -- the real unit instead of hard-coding "m".
            local units = type(out.current_units) == "table" and out.current_units or {}
            local text = string.format("%.1f%s", shown, units.wave_height or "m")
            local period = tonumber(cur.wave_period)
            if period and period > 0 then
                text = text .. string.format(" \u{00B7} %ds", math.floor(period + 0.5))
            end
            surf:set({
                icon = { color = firing and p.accent2 or dim },
                label = { string = text, color = firing and p.accent2 or dim },
            })
        end)
    end

    surf:subscribe({ "routine", "forced", "system_woke" }, fetch)
    fetch()
end

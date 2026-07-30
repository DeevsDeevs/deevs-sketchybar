return function(ctx)
    local p = ctx.palette
    local cfg = ctx.config.surf or {}
    -- Unset lat/lon uses the machine's location; the marine grid snaps an inland fix to water.
    local lat, lon = tonumber(cfg.lat), tonumber(cfg.lon)
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

    -- lua_Number tostring is locale-sensitive ("38,68") and can go scientific; either corrupts the query string.
    local function coord(n) return (string.format("%.4f", n):gsub(",", ".")) end
    local point = lat and lon
        and ("latitude=" .. coord(lat) .. "&longitude=" .. coord(lon)) or nil

    local function query(where)
        -- string.format, never concatenation: it can drop an operand here.
        sbar.exec(string.format(
            "curl -s --max-time 8 'https://marine-api.open-meteo.com/v1/marine?%s&current=wave_height,wave_period'",
            where), function(out)
            -- SbarLua parses JSON stdout into a table; a non-table body is a transport failure, so keep the last reading.
            if type(out) ~= "table" then return end
            -- JSON null arrives as an ABSENT KEY; no .current means answered-but-no-data, so degrade visibly.
            local cur = type(out.current) == "table" and out.current or {}
            local height = tonumber(cur.wave_height)
            if not height then
                surf:set({ icon = { color = dim }, label = { string = "--", color = dim } })
                return
            end
            local shown = math.floor(height * 10 + 0.5) / 10
            local firing = shown >= up
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

    local function fetch()
        if point then return query(point) end
        ctx.locate(function(where)
            if not where then return end
            point = where
            query(where)
        end)
    end

    surf:subscribe({ "routine", "forced", "system_woke" }, fetch)
    fetch()
end

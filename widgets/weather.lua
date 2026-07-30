return function(ctx)
    local p = ctx.palette
    local cfg = ctx.config.weather or {}

    local weather = sbar.add("item", "widgets.weather", {
        position = "right",
        icon = { string = "\u{f0595}", font = { size = 13.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = { string = "--°", font = { family = ctx.settings.font.numbers }, color = ctx.with_alpha(p.fg, 0.7) },
        -- 30s until the first reading (fetch relaxes to 900): boot can beat wifi, and exec callbacks fired during config load can be lost.
        update_freq = 30,
    })
    table.insert(ctx.groups.right, weather.name)
    ctx.cluster("status", weather.name)

    -- WMO codes 80-82 are rain showers, not snow.
    local function glyph(code)
        if code >= 95 then return "\u{f0593}" end
        if code >= 85 or (code >= 71 and code <= 77) then return "\u{f0598}" end
        if code >= 51 then return "\u{f0597}" end
        if code >= 45 then return "\u{f0591}" end
        if code >= 1 then return "\u{f0595}" end
        return "\u{f0599}"
    end

    -- No jq: SbarLua parses JSON stdout into a lua table.
    local point
    local function fetch()
        -- string.format, never `..`: concatenation can drop an operand here.
        sbar.exec(string.format(
            "curl -s --max-time 8 'https://api.open-meteo.com/v1/forecast?%s&current=temperature_2m,weather_code'",
            point), function(out)
            local current = type(out) == "table" and out.current
            if not (current and current.temperature_2m and current.weather_code) then return end
            weather:set({
                update_freq = 900,
                icon = { string = glyph(current.weather_code) },
                label = { string = math.floor(current.temperature_2m + 0.5) .. "°" },
            })
        end)
    end

    local function geocode()
        sbar.exec(string.format(
            "curl -s --max-time 8 -G 'https://geocoding-api.open-meteo.com/v1/search?count=1' --data-urlencode %s",
            ctx.shell_quote(string.format("name=%s", cfg.place))), function(out)
            if type(out) ~= "table" then return end
            local hit = out.results and out.results[1]
            if not (hit and hit.latitude) then
                return weather:set({ update_freq = 900 })
            end
            point = string.format("latitude=%s&longitude=%s", hit.latitude, hit.longitude)
            fetch()
        end)
    end

    local function render()
        if point then return fetch() end
        if cfg.place then return geocode() end
        ctx.locate(function(where)
            if not where then return end
            point = where
            fetch()
        end)
    end

    weather:subscribe({ "routine", "forced", "system_woke" }, render)
    render()
end

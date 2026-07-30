return function(ctx)
    local p = ctx.palette
    local cfg = ctx.config.weather or {}
    -- Without a place there is nothing to look up; hide like any widget whose
    -- dependency is missing rather than sitting there as a dead "--°".
    if not cfg.place then return end

    local weather = sbar.add("item", "widgets.weather", {
        position = "right",
        icon = { string = "\u{f0595}", font = { size = 13.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = { string = "--°", font = { family = ctx.settings.font.numbers }, color = ctx.with_alpha(p.fg, 0.7) },
        -- 30s only until the first reading lands (fetch relaxes it to 900):
        -- the bar routinely loads before wifi is up, and exec callbacks fired
        -- during config can be lost, so the first routine tick has to arrive
        -- soon enough to not look broken.
        update_freq = 30,
    })
    table.insert(ctx.groups.right, weather.name)
    ctx.cluster("status", weather.name)

    -- WMO code ranges, coarsened to the six glyphs that read at bar size.
    -- 80-82 are rain showers; only 71-77 and 85/86 are snow.
    local function glyph(code)
        if code >= 95 then return "\u{f0593}" end                                -- thunder
        if code >= 85 or (code >= 71 and code <= 77) then return "\u{f0598}" end -- snow
        if code >= 51 then return "\u{f0597}" end                                -- drizzle/rain/showers
        if code >= 45 then return "\u{f0591}" end                                -- fog
        if code >= 1 then return "\u{f0595}" end                                 -- clouds
        return "\u{f0599}"                                                       -- clear
    end

    -- No jq: SbarLua parses JSON stdout and hands the callback a lua table, so a
    -- pipe would only add a fork to reach the same fields. (macOS 15 does ship
    -- /usr/bin/jq, so a bare PATH is not the reason.)
    local point
    local function fetch()
        sbar.exec("curl -s --max-time 8 " .. ctx.shell_quote(
            "https://api.open-meteo.com/v1/forecast?" .. point .. "&current=temperature_2m,weather_code"),
            function(out)
            local current = type(out) == "table" and out.current
            -- On failure keep the last reading: a stale temperature is more
            -- truthful than "--°" flapping on every network blip.
            if not (current and current.temperature_2m and current.weather_code) then return end
            weather:set({
                update_freq = 900,
                icon = { string = glyph(current.weather_code) },
                label = { string = math.floor(current.temperature_2m + 0.5) .. "°" },
            })
        end)
    end

    -- -G --data-urlencode, not string concatenation: place names have spaces in
    -- them ("San Francisco") and a raw space makes the request URL invalid.
    local function geocode()
        sbar.exec("curl -s --max-time 8 -G 'https://geocoding-api.open-meteo.com/v1/search?count=1'"
            .. " --data-urlencode " .. ctx.shell_quote("name=" .. cfg.place), function(out)
            if type(out) ~= "table" then return end
            local hit = out.results and out.results[1]
            if not (hit and hit.latitude) then
                -- The API answered and doesn't know the place: a config typo,
                -- so stop the 30s bootstrap instead of hammering it forever.
                return weather:set({ update_freq = 900 })
            end
            point = "latitude=" .. hit.latitude .. "&longitude=" .. hit.longitude
            fetch()
        end)
    end

    -- Geocoding must stay retryable rather than one-shot at load: a laptop
    -- that boots faster than wifi would otherwise never resolve the place and
    -- the widget would be dead until the next config reload.
    local function render()
        if point then fetch() else geocode() end
    end

    weather:subscribe({ "routine", "forced", "system_woke" }, render)
    render()
end

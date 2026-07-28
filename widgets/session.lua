-- Session.app pomodoro: live countdown via an alias of Session's own status
-- item (zero polling), controls via session:/// deep links, stats from the
-- shared sqlite in the "translucent" group container (Session's original name).
return function(ctx)
    local p, style = ctx.palette, ctx.style
    local conf = ctx.config.session

    local alias = sbar.add("alias", conf.alias, {
        position = "right",
        alias = { color = p.accent },
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        icon = { drawing = false },
        label = { drawing = false },
        padding_left = 2,
        padding_right = 2,
        update_freq = 2,
        popup = { align = "right" },
    })
    table.insert(ctx.groups.right, alias.name)

    for _, action in ipairs({
        { label = "pause / resume", link = "session:///pause" },
        { label = "start previous", link = "session:///start-previous" },
        { label = "break", link = "session:///break" },
        { label = "finish", link = "session:///finish" },
        { label = "abandon", link = "session:///abandon" },
    }) do
        sbar.add("item", {
            position = "popup." .. alias.name,
            icon = { drawing = false },
            label = { string = action.label, padding_left = 10, padding_right = 10 },
            click_script = "open " .. ctx.shell_quote(action.link)
                .. "; sketchybar --set " .. ctx.shell_quote(alias.name) .. " popup.drawing=off",
        })
    end

    local db = os.getenv("HOME")
        .. "/Library/Group Containers/98JSB2MQB3.group.com.philipyoungg.translucent/Session.sqlite"
    local today_query = "sqlite3 -readonly " .. ctx.shell_quote("file:" .. db .. "?mode=ro")
        .. [[ "SELECT count(*), coalesce(sum(ZENDDATE-ZSTARTDATE)/60,0) FROM ZSESSIONTASK ]]
        .. [[WHERE date(ZSTARTDATE+978307200,'unixepoch','localtime') = date('now','localtime');" 2>/dev/null]]

    local stats = sbar.add("item", {
        position = "popup." .. alias.name,
        icon = { drawing = false },
        label = { string = "…", color = ctx.with_alpha(p.fg, 0.55), padding_left = 10, padding_right = 10 },
    })

    alias:subscribe("mouse.clicked", function()
        sbar.exec(today_query, function(out)
            local n, mins = tostring(out):match("(%d+)|(%d+)")
            if n then
                stats:set({ label = string.format("today · %s sessions · %dh %02dm",
                    n, math.floor(mins / 60), mins % 60) })
            end
        end)
        alias:set({ popup = { drawing = "toggle" } })
    end)
    alias:subscribe("mouse.exited.global", function()
        alias:set({ popup = { drawing = false } })
    end)
end

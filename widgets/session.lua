-- Session.app pomodoro. Countdown comes from Session's shared sqlite (the
-- "translucent" group container — Session's original name): a running session
-- is simply the latest task whose end date is still in the future.
-- Controls via session:/// deep links. No alias — with the native menubar
-- hidden, aliases capture a blank region.
return function(ctx)
    local p, style = ctx.palette, ctx.style

    local db = os.getenv("HOME")
        .. "/Library/Group Containers/98JSB2MQB3.group.com.philipyoungg.translucent/Session.sqlite"
    local q = function(sql)
        return "sqlite3 -readonly " .. ctx.shell_quote("file:" .. db .. "?mode=ro") .. " "
            .. ctx.shell_quote(sql) .. " 2>/dev/null"
    end

    local chip = sbar.add("item", "session", {
        position = "right",
        drawing = false,
        updates = true,
        icon = { string = "󰔛", color = p.accent, font = { size = 13.0 } },
        label = { string = "", font = { family = ctx.settings.font.numbers } },
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        update_freq = 30,
        popup = { align = "center" },
    })
    table.insert(ctx.groups.right, chip.name)

    for _, action in ipairs({
        { label = "pause / resume", link = "session:///pause" },
        { label = "start previous", link = "session:///start-previous" },
        { label = "break", link = "session:///break" },
        { label = "finish", link = "session:///finish" },
        { label = "abandon", link = "session:///abandon" },
    }) do
        sbar.add("item", {
            position = "popup." .. chip.name,
            icon = { drawing = false },
            label = { string = action.label, padding_left = 10, padding_right = 10 },
            click_script = "open " .. ctx.shell_quote(action.link)
                .. "; sketchybar --set session popup.drawing=off",
        })
    end
    local stats = sbar.add("item", {
        position = "popup." .. chip.name,
        icon = { drawing = false },
        label = { string = "…", color = ctx.with_alpha(p.fg, 0.55), padding_left = 10, padding_right = 10 },
    })

    -- Latest task still running → minutes remaining; else hide the chip.
    local remaining_sql = [[SELECT cast((max(ZENDDATE) - (strftime('%s','now') - 978307200)) / 60 as int)
        FROM ZSESSIONTASK WHERE ZENDDATE > (strftime('%s','now') - 978307200);]]

    local function refresh()
        sbar.exec(q(remaining_sql), function(out)
            local mins = tonumber(tostring(out):match("%-?%d+"))
            if mins and mins >= 0 then
                chip:set({ drawing = true, label = { string = mins .. "m" } })
            else
                chip:set({ drawing = false, popup = { drawing = false } })
            end
        end)
    end

    chip:subscribe({ "routine", "forced", "system_woke" }, refresh)
    refresh()

    chip:subscribe("mouse.clicked", function()
        sbar.exec(q([[SELECT count(*) || '|' || cast(coalesce(sum(ZENDDATE-ZSTARTDATE)/60,0) as int)
            FROM ZSESSIONTASK WHERE date(ZSTARTDATE+978307200,'unixepoch','localtime') = date('now','localtime');]]),
            function(out)
                local n, mins = tostring(out):match("(%d+)|(%d+)")
                if n then
                    stats:set({ label = string.format("today · %s sessions · %dh %02dm",
                        n, math.floor(mins / 60), mins % 60) })
                end
            end)
        chip:set({ popup = { drawing = "toggle" } })
    end)
    chip:subscribe("mouse.exited.global", function()
        chip:set({ popup = { drawing = false } })
    end)
end

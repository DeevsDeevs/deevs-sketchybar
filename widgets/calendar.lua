return function(ctx)
    local p, style = ctx.palette, ctx.style

    local cal = sbar.add("item", "widgets.calendar", {
        position = "right",
        icon = { drawing = false },
        label = {
            font = { family = ctx.settings.font.numbers, style = "Bold", size = 12.5 },
            color = p.fg,
            padding_left = 8,
            padding_right = 8,
        },
        update_freq = 30,
        click_script = "open -a Calendar",
    })
    table.insert(ctx.groups.right, cal.name)

    cal:subscribe({ "forced", "routine", "system_woke" }, function()
        cal:set({ label = os.date("%a %d · %H:%M") })
    end)
end

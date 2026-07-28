return function(ctx)
    local p, style = ctx.palette, ctx.style

    local cal = sbar.add("item", "widgets.calendar", {
        position = "right",
        icon = {
            font = { family = ctx.settings.font.text, style = "Bold", size = 11.0 },
            color = ctx.with_alpha(p.fg, 0.7),
            padding_left = 8,
        },
        label = {
            font = { family = ctx.settings.font.numbers, style = "Bold", size = 12.0 },
            color = p.fg,
            padding_right = 8,
            align = "right",
        },
        background = { color = style.item_bg, corner_radius = style.item_radius, height = style.item_height },
        update_freq = 30,
        click_script = "open -a Calendar",
    })
    table.insert(ctx.groups.right, cal.name)

    cal:subscribe({ "forced", "routine", "system_woke" }, function()
        cal:set({ icon = os.date("%a %d %b"), label = os.date("%H:%M") })
    end)
end

return function(ctx)
    local item = sbar.add("item", "brand", {
        position = "left",
        icon = { string = (ctx.config.bar or {}).icon or "", color = ctx.palette.accent, font = { size = 15.0 } },
        label = { drawing = false },
        padding_right = 4,
        click_script = "sketchybar --reload",
    })
    table.insert(ctx.groups.left, item.name)
end

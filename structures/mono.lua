-- Text-first: fully transparent bar, no chips, wide gaps. Mostly deletion.
local M = {}

function M.style(ctx)
    local p = ctx.palette
    return {
        item_bg = p.transparent,
        item_radius = 0,
        item_height = 28,
        popup_bg = ctx.with_alpha(p.bg, 0.96),
        popup_radius = 10,
    }
end

function M.apply(ctx)
    local p, c = ctx.palette, ctx.config
    sbar.bar({
        height = c.bar.height,
        color = p.transparent,
        padding_left = 12,
        padding_right = 12,
        topmost = "on",
        show_in_fullscreen = "on",
    })
    sbar.default({
        updates = "when_shown",
        padding_left = 7,
        padding_right = 7,
        icon = {
            font = { family = ctx.settings.font.text, style = "Medium", size = 12.0 },
            color = ctx.with_alpha(p.fg, 0.85),
            padding_left = 4,
            padding_right = 4,
        },
        label = {
            font = { family = ctx.settings.font.text, style = "Regular", size = 11.5 },
            color = ctx.with_alpha(p.fg, 0.85),
            padding_left = 4,
            padding_right = 4,
        },
        background = { drawing = false },
        popup = {
            background = {
                border_width = 1,
                border_color = ctx.with_alpha(p.fg, 0.12),
                corner_radius = 10,
                color = ctx.with_alpha(p.bg, 0.96),
            },
        },
    })
end

return M

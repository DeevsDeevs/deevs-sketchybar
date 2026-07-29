-- One floating translucent slab. Hierarchy by opacity, not borders.
local M = {}

function M.style(ctx)
    local p = ctx.palette
    return {
        item_bg = p.chip,
        item_radius = 8,
        item_height = 28,
        popup_bg = ctx.with_alpha(p.bg, 0.94),
        popup_radius = 12,
    }
end

function M.apply(ctx)
    local p, c = ctx.palette, ctx.config
    sbar.bar({
        height = c.bar.height,
        color = ctx.with_alpha(p.bg, c.glass or 0.9),
        border_width = 1,
        border_color = ctx.with_alpha(p.fg, 0.14),
        corner_radius = 13,
        margin = 10,
        y_offset = 6,
        blur_radius = 30,
        padding_left = 10,
        padding_right = 10,
        shadow = "on",
        topmost = "on",
        show_in_fullscreen = "on",
    })
    sbar.default({
        updates = "when_shown",
        -- Room for ctx.chip's inset to live in: the bracket's padding doubles
        -- as its background inset, so with items flush to the edge any gap
        -- between chips is carved out of their own contents.
        padding_left = 8,
        padding_right = 8,
        icon = {
            font = { family = ctx.settings.font.text, style = "SemiBold", size = 13.0 },
            color = p.fg,
            padding_left = 5,
            padding_right = 5,
        },
        label = {
            font = { family = ctx.settings.font.text, style = "Medium", size = 11.5 },
            color = p.fg,
            padding_left = 5,
            padding_right = 5,
        },
        background = { height = 28, corner_radius = 8, border_width = 0 },
        popup = {
            background = {
                border_width = 1,
                border_color = ctx.with_alpha(p.fg, 0.14),
                corner_radius = 12,
                color = ctx.with_alpha(p.bg, 0.94),
                shadow = { drawing = true },
            },
            blur_radius = 30,
        },
    })
end

return M

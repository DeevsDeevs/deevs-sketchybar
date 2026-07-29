-- No bar at all: floating pill clusters with wallpaper between them.
-- Widgets register their item names in ctx.groups; finish() wraps them in pods.
local M = {}

function M.style(ctx)
    local p = ctx.palette
    return {
        item_bg = p.transparent, -- pods carry the background, items stay naked
        item_radius = 8,
        item_height = 28,
        popup_bg = ctx.with_alpha(p.bg, 0.94),
        popup_radius = 14,
        islands = true,
    }
end

function M.apply(ctx)
    local p, c = ctx.palette, ctx.config
    sbar.bar({
        height = c.bar.height + 6,
        color = p.transparent,
        padding_left = 8,
        padding_right = 8,
        topmost = "on",
        show_in_fullscreen = "on",
    })
    sbar.default({
        updates = "when_shown",
        padding_left = 3,
        padding_right = 3,
        icon = {
            font = { family = ctx.settings.font.text, style = "SemiBold", size = 13.0 },
            color = p.fg, padding_left = 5, padding_right = 5,
        },
        label = {
            font = { family = ctx.settings.font.text, style = "Medium", size = 11.5 },
            color = p.fg, padding_left = 5, padding_right = 5,
        },
        background = { height = 28, corner_radius = 8, border_width = 0 },
        popup = {
            background = {
                border_width = 1,
                border_color = ctx.with_alpha(p.fg, 0.14),
                corner_radius = 14,
                color = ctx.with_alpha(p.bg, 0.94),
            },
        },
    })
end

function M.finish(ctx)
    local p = ctx.palette
    local function pod(members)
        if #members == 0 then return end
        sbar.add("bracket", members, {
            background = {
                color = ctx.with_alpha(p.bg, math.max(ctx.config.glass or 0.85, 0.8)),
                corner_radius = 20,
                height = 40,
                border_width = 1,
                border_color = ctx.with_alpha(p.fg, 0.12),
            },
        })
    end
    pod(ctx.groups.left)
    pod(ctx.groups.center)
    pod(ctx.groups.right)
end

return M

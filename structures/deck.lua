-- Glass, but a bottom deck. tmux owns the top of your screen, this owns the floor.
local glass = require("structures.glass")
local M = {}

M.style = glass.style

function M.apply(ctx)
    glass.apply(ctx)
    sbar.bar({ position = "bottom", height = ctx.config.bar.height + 4, margin = 30, y_offset = 8 })
end

return M

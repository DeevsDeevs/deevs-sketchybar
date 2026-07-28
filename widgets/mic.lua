return function(ctx)
    local p = ctx.palette

    local mic = sbar.add("item", "widgets.mic", {
        position = "right",
        icon = { string = "󰍬", font = { size = 12.0 }, color = ctx.with_alpha(p.fg, 0.6) },
        label = { drawing = false },
        update_freq = 20,
    })
    table.insert(ctx.groups.right, mic.name)

    local function render()
        sbar.exec("osascript -e 'input volume of (get volume settings)'", function(out)
            local muted = tonumber(tostring(out):match("%d+")) == 0
            mic:set({ icon = { string = muted and "󰍭" or "󰍬", color = muted and p.bad or ctx.with_alpha(p.fg, 0.6) } })
        end)
    end

    mic:subscribe({ "routine", "forced" }, render)
    mic:subscribe("mouse.clicked", function()
        sbar.exec([[osascript -e 'set current to input volume of (get volume settings)' -e 'if current is 0 then' -e 'set volume input volume 75' -e 'else' -e 'set volume input volume 0' -e 'end if']],
            function() render() end)
    end)
end

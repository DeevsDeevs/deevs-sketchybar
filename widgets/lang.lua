return function(ctx)
    local p = ctx.palette

    local function short_id(raw)
        return tostring(raw):match("([%w%-]+)%s*$")
    end

    local names = { US = "EN", ABC = "EN", Russian = "RU", British = "EN" }
    -- Normalise config keys so both "Russian" and "com.apple.keylayout.Russian" work.
    for id, short in pairs((ctx.config.lang or {}).names or {}) do
        names[short_id(id) or id] = short
    end

    local lang = sbar.add("item", "widgets.lang", {
        position = "right",
        icon = { drawing = false },
        label = { string = "··", font = { style = "Bold", size = 10.5 }, color = ctx.with_alpha(p.fg, 0.8) },
        update_freq = 2,
        -- The legacy Keyboard.prefPane URL opens on General; this one lands on Keyboard.
        click_script = "open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'",
    })
    table.insert(ctx.groups.right, lang.name)
    ctx.cluster("status", lang.name)

    local function render()
        -- No layout-change event reachable from here (TIS needs a native observer), so poll.
        sbar.exec("defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID 2>/dev/null", function(out)
            local id = short_id(out)
            if not id then return end
            -- %w is ASCII-only, so byte-wise sub/upper is safe.
            lang:set({ label = names[id] or id:sub(1, 2):upper() })
        end)
    end

    lang:subscribe({ "routine", "forced" }, render)
    render()
end

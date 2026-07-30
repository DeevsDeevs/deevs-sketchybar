return function(ctx)
    local p = ctx.palette
    local conf = type(ctx.config.herdr) == "table" and ctx.config.herdr or {}
    local hosts = conf.hosts or { { name = "local" } }
    local fleet = {}

    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and (str:sub(1, cut - 1) .. "…") or str
    end

    local chip = sbar.add("item", "herdr", {
        position = "right",
        icon = { string = "✳", color = ctx.with_alpha(p.fg, 0.5), font = { size = 12.0 } },
        label = { string = "—", font = { family = ctx.settings.font.numbers } },
        update_freq = conf.poll or 5,
        updates = true, -- default when_shown gets no routine while drawing=false, so a hidden chip could never return
        popup = { align = "right" },
    })
    table.insert(ctx.groups.right, chip.name)
    local backdrop = ctx.chip("herdr.chip", { chip.name })

    -- ConnectTimeout bounds only the handshake; ServerAlive deadlines the established session.
    local function host_cmd(host)
        if host.ssh then
            return "ssh -o BatchMode=yes -o ConnectTimeout=2"
                .. " -o ServerAliveInterval=2 -o ServerAliveCountMax=2 "
                .. ctx.shell_quote(host.ssh) .. " herdr agent list 2>/dev/null"
        end
        return "herdr agent list 2>/dev/null"
    end

    local function render_chip()
        local working, blocked, total = 0, 0, 0
        for _, agents in pairs(fleet) do
            for _, a in ipairs(agents) do
                total = total + 1
                if a.agent_status == "working" then working = working + 1 end
                if a.agent_status == "blocked" then blocked = blocked + 1 end
            end
        end
        if total == 0 then
            chip:set({ drawing = false })
            backdrop:set({ drawing = false })
            return
        end
        backdrop:set({ drawing = true })
        chip:set({
            drawing = true,
            icon = { color = blocked > 0 and p.bad or (working > 0 and p.accent or ctx.with_alpha(p.fg, 0.5)) },
            label = {
                string = blocked > 0 and (working .. "⚡ " .. blocked .. "󰀦") or (working > 0 and working .. "⚡" or tostring(total)),
                color = blocked > 0 and p.bad or p.fg,
            },
        })
    end

    local function render_popup()
        sbar.remove("/herdr\\.row\\..*/")
        local order = { blocked = 1, working = 2, done = 3, idle = 4 }
        local n = 0
        for _, host in ipairs(hosts) do
            local agents = fleet[host.name] or {}
            table.sort(agents, function(a, b)
                return (order[a.agent_status] or 9) < (order[b.agent_status] or 9)
            end)
            for _, a in ipairs(agents) do
                n = n + 1
                local dot = a.agent_status == "blocked" and p.bad
                    or a.agent_status == "working" and p.accent
                    or a.agent_status == "done" and p.good
                    or ctx.with_alpha(p.fg, 0.3)
                local title = (a.terminal_title_stripped or a.terminal_title or a.agent or "?")
                local focus = host.ssh
                    and ("ssh -o BatchMode=yes " .. ctx.shell_quote(host.ssh) .. " herdr agent focus " .. ctx.shell_quote(a.pane_id))
                    or ("herdr agent focus " .. ctx.shell_quote(a.pane_id))
                sbar.add("item", "herdr.row." .. n, {
                    position = "popup." .. chip.name,
                    icon = {
                        string = "●",
                        color = dot,
                        font = { size = 9.0 },
                        padding_left = 8,
                    },
                    label = {
                        string = string.format("%s %s  ·  %s", a.agent == "claude" and "✳" or "π",
                            clip(title, 42), host.name),
                        padding_right = 10,
                    },
                    click_script = focus .. "; sketchybar --set herdr popup.drawing=off",
                })
            end
        end
        if n == 0 then
            sbar.add("item", "herdr.row.0", {
                position = "popup." .. chip.name,
                icon = { drawing = false },
                label = { string = "no agents running", color = ctx.with_alpha(p.fg, 0.5) },
            })
        end
    end

    local function poll()
        for _, host in ipairs(hosts) do
            sbar.exec(host_cmd(host), function(result)
                if type(result) == "table" and result.result and result.result.agents then
                    fleet[host.name] = result.result.agents
                elseif not host.ssh then
                    fleet[host.name] = {}
                end
                render_chip()
            end)
        end
    end

    chip:subscribe("routine", poll)
    chip:subscribe("forced", poll)
    chip:subscribe("mouse.clicked", function()
        render_popup()
        chip:set({ popup = { drawing = "toggle" } })
    end)
    chip:subscribe("mouse.exited.global", function()
        chip:set({ popup = { drawing = false } })
    end)
    poll()
end

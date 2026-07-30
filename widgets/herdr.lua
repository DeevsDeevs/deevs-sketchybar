return function(ctx)
    local p = ctx.palette
    local conf = type(ctx.config.herdr) == "table" and ctx.config.herdr or {}
    local fixed, follows = ctx.host_of(conf)
    local target = fixed or (follows and ((ctx.config.servers or {}).default or "local")) or nil
    local fleet = {}

    -- A target collapses the fleet to one host; untargeted, the configured list stands.
    local function resolve()
        if not target then return conf.hosts or { { name = "local" } } end
        if target == "local" then return { { name = "local" } } end
        return { { name = target, ssh = target } }
    end
    local hosts = resolve()

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

    -- `$SHELL -ic`, not a bare command: version managers put herdr on PATH from the
    -- interactive rc, which plain ssh never sources, and the host then reads as
    -- "no agents" while agents are running on it.
    -- string.format, never `..`: concatenation drops an operand and builds
    -- `-o ConnectTimeout=4'host'`, which ssh rejects with empty stdout.
    -- ConnectTimeout bounds only the handshake; ServerAlive deadlines the live session.
    local function over_ssh(host, command)
        return string.format(
            "ssh -o BatchMode=yes -o ConnectTimeout=4 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 %s %s",
            ctx.shell_quote(host.ssh),
            ctx.shell_quote(string.format("$SHELL -ic %s", ctx.shell_quote(command))))
    end

    local function host_cmd(host)
        if host.ssh then
            return string.format("%s 2>/dev/null", over_ssh(host, "herdr agent list"))
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
                    and over_ssh(host, string.format("herdr agent focus %s", ctx.shell_quote(a.pane_id)))
                    or string.format("herdr agent focus %s", ctx.shell_quote(a.pane_id))
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

    -- A reply from the host we just left would land after the reset and be counted into
    -- the new one. Bumped only on retarget, so a slow reply from the current host still lands.
    local epoch = 0

    local function poll()
        local mine = epoch
        for _, host in ipairs(hosts) do
            sbar.exec(host_cmd(host), function(result)
                if mine ~= epoch then return end
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

    if follows then
        sbar.add("event", "host_change")
        chip:subscribe("host_change", function(env)
            if not env.HOST or env.HOST == "" or env.HOST == target then return end
            target = env.HOST
            hosts = resolve()
            fleet = {}
            epoch = epoch + 1
            poll()
        end)
    end
    poll()
end

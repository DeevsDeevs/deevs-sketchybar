return function(ctx)
    ctx.owns_popup()
    local p = ctx.palette
    local conf = type(ctx.config.herdr) == "table" and ctx.config.herdr or {}
    local fleet, tab_labels, offline = {}, {}, {}

    -- Local first, then every enabled saved machine (`herdr machine add`). herdr owns
    -- the SSH side, so a machine is addressed by its profile id, never by an ssh alias.
    local hosts = { { name = "local" } }

    -- herdr drives 22 agent kinds; only these two have a mark worth showing, and the rest
    -- get a neutral robot rather than being mislabelled as pi.
    local GLYPH = { pi = "π", claude = "✳" }
    local FALLBACK = "\u{f06a9}"
    local function glyph_of(agent)
        return GLYPH[agent] or FALLBACK
    end

    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and (str:sub(1, cut - 1) .. "…") or str
    end

    local chip = sbar.add("item", "herdr", {
        position = "right",
        icon = {
            string = "✳",
            color = ctx.with_alpha(p.fg, 0.5),
            font = { size = 12.0 },
            padding_right = 3,
        },
        label = {
            string = "—",
            font = { family = ctx.settings.font.numbers },
            padding_left = 0,
        },
        update_freq = conf.poll or 5,
        updates = true, -- default when_shown gets no routine while drawing=false, so a hidden chip could never return
        -- Unset, a popup row inherits the bar's 28pt item height and lands ~40pt apart,
        -- which turns a fleet into a wall.
        popup = { align = "right", height = 22 },
    })
    table.insert(ctx.groups.right, chip.name)
    local backdrop = ctx.chip("herdr.chip", { chip.name })

    -- A red number on a 12pt chip is easy to walk past, so a blocked agent tints the slab
    -- and breathes the glyph — only while something is actually waiting on you.
    local ALERT_TINT, ALERT_REST = 0.18, 0.45
    local alerting, lit = false, false
    -- Its own item: the chip polls on `poll` seconds and a breath wants its own second.
    -- The tint is set flat rather than animated — sbar.animate does nothing to a
    -- bracket's background, the colour simply stays put.
    local pulse = sbar.add("item", "herdr.pulse", {
        drawing = false,
        updates = true,
        update_freq = 1,
    })
    pulse:subscribe("routine", function()
        if not alerting then return end
        lit = not lit
        sbar.animate("sin", 28, function()
            local shade = lit and p.bad or ctx.with_alpha(p.bad, ALERT_REST)
            chip:set({ icon = { color = shade }, label = { color = shade } })
        end)
    end)

    local function host_cmd(host, args)
        if host.machine then
            return string.format("herdr --machine %s %s 2>/dev/null", ctx.shell_quote(host.machine), args)
        end
        return string.format("herdr %s 2>/dev/null", args)
    end

    -- The chip wears the mark of whichever agent it is reporting on: whatever is blocked,
    -- else whatever is running, else the one that moved last. state_change_seq is herdr's
    -- own counter, so ties resolve to the most active agent even when nothing is running.
    local TIER = { blocked = 1, working = 2 }
    local function outranks(a, b)
        local ra, rb = TIER[a.agent_status] or 3, TIER[b.agent_status] or 3
        if ra ~= rb then return ra < rb end
        return (tonumber(a.state_change_seq) or 0) > (tonumber(b.state_change_seq) or 0)
    end

    local function render_chip()
        local working, blocked, total = 0, 0, 0
        local lead
        for _, agents in pairs(fleet) do
            for _, a in ipairs(agents) do
                total = total + 1
                if a.agent_status == "working" then working = working + 1 end
                if a.agent_status == "blocked" then blocked = blocked + 1 end
                if not lead or outranks(a, lead) then lead = a end
            end
        end
        if total == 0 and blocked == 0 then
            chip:set({ drawing = false })
            backdrop:set({ drawing = false })
            return
        end
        -- One number, coloured. U+26A1 and the alert glyph fall back off JetBrainsMono
        -- and render oversized; at this size colour carries the state anyway.
        local count, color = total, ctx.with_alpha(p.fg, 0.7)
        if blocked > 0 then
            count, color = blocked, p.bad
        elseif working > 0 then
            count, color = working, p.accent
        end

        -- Settle back in one step: leaving it mid-breath strands the slab on whatever
        -- alpha the last frame happened to land on.
        if (blocked > 0) ~= alerting then
            alerting = blocked > 0
            lit = false
            backdrop:set({ background = {
                color = alerting and ctx.with_alpha(p.bad, ALERT_TINT) or ctx.style.item_bg,
            } })
        end

        backdrop:set({ drawing = true })
        local paint = {
            drawing = true,
            icon = { string = glyph_of(lead and lead.agent) },
            label = { string = tostring(count) },
        }
        -- While alerting the breath owns the colour; repainting it here would snap the
        -- glyph back to full on every poll.
        if not alerting then
            paint.icon.color, paint.label.color = color, color
        end
        chip:set(paint)
    end

    -- Survives re-render so a group you opened stays open.
    local expanded = {}

    local function leaf_of(a)
        return (a.cwd or ""):match("[^/]+$") or "—"
    end

    -- Two checkouts can share a leaf — tasks/dagster-setup/core-platform and
    -- tasks/auth-redpanda/core-platform — and grouping on it alone files their agents
    -- together. Grow the label leftward only until every project is distinct.
    local function project_names(entries)
        local segs, depth, out = {}, {}, {}
        for _, e in ipairs(entries) do
            local path = e.a.cwd or ""
            if not segs[path] then
                segs[path] = {}
                for part in path:gmatch("[^/]+") do table.insert(segs[path], part) end
                depth[path] = 1
            end
        end
        for _ = 1, 5 do
            local seen, clash = {}, false
            for path, list in pairs(segs) do
                out[path] = #list > 0
                    and table.concat(list, "/", math.max(1, #list - depth[path] + 1))
                    or "—"
                seen[out[path]] = (seen[out[path]] or 0) + 1
            end
            for path, list in pairs(segs) do
                if seen[out[path]] > 1 and depth[path] < #list then
                    depth[path] = depth[path] + 1
                    clash = true
                end
            end
            if not clash then break end
        end
        return out
    end

    -- The pane is on every row: it is the only thing that tells sibling agents in one
    -- project apart, and the one thing you need to find the agent once you get there.
    -- "π - tracing" beside a "tracing" heading says nothing twice, so that row is the
    -- pane alone rather than the title repeated.
    local function row_text(a, host)
        -- The tab's own name, which is what you called it. herdr numbers tabs nobody
        -- renamed, and "3" tells you less than the pane does.
        local label = (tab_labels[host.name] or {})[a.tab_id]
        if not label or label:match("^%d+$") then
            label = (a.pane_id or ""):match("[^:]+$") or "?"
        end
        local title = a.terminal_title_stripped or a.terminal_title or ""
        local tail = title:match("^%S+%s+%-%s+(.+)$")
        if title == "" or tail == leaf_of(a) then
            return label
        end
        return string.format("%s  %s", label, clip(title, 34))
    end

    -- Everything the popup draws, in one string. A rebuild is ~25 items on the wire and
    -- blocks the bar, and most opens follow a poll that changed nothing. Expanded groups
    -- are left out on purpose: their click handler flips rows it already built.
    local function signature()
        local parts = {}
        for _, host in ipairs(hosts) do
            parts[#parts + 1] = host.name
            local labels = tab_labels[host.name] or {}
            for _, a in ipairs(fleet[host.name] or {}) do
                parts[#parts + 1] = string.format("%s|%s|%s|%s|%s|%s|%s",
                    tostring(a.agent), tostring(a.agent_status), tostring(a.cwd),
                    tostring(a.pane_id), tostring(a.focused),
                    tostring(a.terminal_title_stripped or a.terminal_title),
                    tostring(labels[a.tab_id]))
            end
        end
        for name in pairs(offline) do parts[#parts + 1] = name .. "=offline" end
        table.sort(parts)
        return table.concat(parts, "\n")
    end

    local drawn_signature
    local function render_popup()
        local current = signature()
        if current == drawn_signature then return end
        drawn_signature = current
        sbar.remove("/herdr\\.row\\..*/")
        local n = 0
        local multi = #hosts > 1

        local function section(text, count, color)
            n = n + 1
            return sbar.add("item", "herdr.row." .. n, {
                position = "popup." .. chip.name,
                icon = { drawing = false },
                label = {
                    string = string.format("%s  %d", text, count),
                    color = color or ctx.with_alpha(p.fg, 0.4),
                    font = { style = "Bold", size = 9.0 },
                    padding_left = 12,
                    padding_right = 14,
                },
            })
        end

        -- Status tints the row itself: a 7pt dot beside the text does not survive being
        -- read at a glance, and the row background is free.
        local function row(a, host, suffix, visible)
            n = n + 1
            local blocked = a.agent_status == "blocked"
            local working = a.agent_status == "working"
            local lead = blocked and "◆" or working and "▶" or a.focused and "▸" or "·"
            local lead_color = blocked and p.bad or working and p.accent
                or a.focused and p.fg or ctx.with_alpha(p.fg, 0.28)
            -- Remote panes live in the same local window, but no API selects a machine in
            -- it: focus the pane on its server and raise the window; the sidebar does the rest.
            local focus = host.machine
                and string.format("(herdr --machine %s agent focus %s >/dev/null 2>&1 &); %s",
                    ctx.shell_quote(host.machine), ctx.shell_quote(a.pane_id),
                    ctx.shell_quote(ctx.helper("herdr_focus.sh")))
                or string.format("%s %s %s", ctx.shell_quote(ctx.helper("herdr_focus.sh")),
                    ctx.shell_quote(a.pane_id), ctx.shell_quote(conf.tab or ""))
            local props = {
                position = "popup." .. chip.name,
                icon = {
                    string = lead,
                    color = lead_color,
                    font = { size = 9.0 },
                    padding_left = 12,
                    padding_right = 7,
                },
                label = {
                    string = string.format("%s %s%s", glyph_of(a.agent),
                        row_text(a, host), suffix or ""),
                    color = (blocked or working) and p.fg or ctx.with_alpha(p.fg, 0.72),
                    font = { size = 11.0 },
                    padding_left = 0,
                    padding_right = 14,
                },
                -- Popup down first, jump second. Dismissing it afterwards handed focus
                -- back to whatever was underneath and undid the raise.
                click_script = string.format(
                    "sketchybar --set herdr popup.drawing=off; %s", focus),
            }
            if visible == false then props.drawing = false end
            if blocked or working then
                props.background = {
                    color = ctx.with_alpha(blocked and p.bad or p.accent, blocked and 0.17 or 0.13),
                    corner_radius = 6,
                    height = 20,
                }
            end
            return sbar.add("item", "herdr.row." .. n, props)
        end

        local entries = {}
        for _, host in ipairs(hosts) do
            for _, a in ipairs(fleet[host.name] or {}) do
                table.insert(entries, { a = a, host = host })
            end
        end
        local names = project_names(entries)
        local function label_of(e)
            local name = names[e.a.cwd or ""] or leaf_of(e.a)
            if multi then return string.format("%s · %s", name, e.host.name) end
            return name
        end

        -- A machine that stopped answering has no agents to list, which reads as idle.
        -- Saying so keeps "nothing running" from being a lie.
        for _, host in ipairs(hosts) do
            if offline[host.name] then
                n = n + 1
                sbar.add("item", "herdr.row." .. n, {
                    position = "popup." .. chip.name,
                    icon = { string = "!", color = p.bad, font = { size = 9.0 },
                        padding_left = 12, padding_right = 7 },
                    label = {
                        string = string.format("%s  unreachable", host.name),
                        color = ctx.with_alpha(p.fg, 0.55),
                        font = { size = 10.5 },
                        padding_left = 0,
                        padding_right = 14,
                    },
                })
            end
        end

        -- Anything waiting on you, then anything moving. Both are few, so both get a
        -- full row with the project spelled out.
        for _, status in ipairs({ "blocked", "working" }) do
            local pick = {}
            for _, e in ipairs(entries) do
                if e.a.agent_status == status then table.insert(pick, e) end
            end
            if #pick > 0 then
                section(status == "blocked" and "needs you" or "running", #pick,
                    status == "blocked" and p.bad or ctx.with_alpha(p.accent, 0.85))
                for _, e in ipairs(pick) do
                    row(e.a, e.host, string.format("   %s", label_of(e)))
                end
            end
        end

        -- Everything else is standby: one line per project rather than fifteen agent rows,
        -- since a popup cannot scroll. Click a project to reach the agents inside it.
        local rest, order = {}, {}
        for _, e in ipairs(entries) do
            local st = e.a.agent_status
            if st ~= "blocked" and st ~= "working" then
                local key = label_of(e)
                if not rest[key] then
                    rest[key] = {}
                    order[#order + 1] = key
                end
                table.insert(rest[key], e)
            end
        end
        table.sort(order)

        if #order > 0 then
            local count = 0
            for _, key in ipairs(order) do count = count + #rest[key] end
            section("standby", count)

            for _, key in ipairs(order) do
                local open = expanded[key] == true
                n = n + 1
                local item = sbar.add("item", "herdr.row." .. n, {
                    position = "popup." .. chip.name,
                    icon = {
                        string = open and "▾" or "▸",
                        color = ctx.with_alpha(p.fg, 0.42),
                        font = { size = 9.0 },
                        padding_left = 12,
                        padding_right = 7,
                    },
                    label = {
                        string = string.format("%s  %d", key, #rest[key]),
                        color = ctx.with_alpha(p.fg, 0.55),
                        font = { size = 10.5 },
                        padding_left = 0,
                        padding_right = 14,
                    },
                })
                -- Built whatever the state, then shown or hidden. Re-rendering instead
                -- would sbar.remove the item under the pointer, and its mouse.exited.global
                -- fires on the way out and shuts the popup — so expanding closed it.
                local kids = {}
                for _, e in ipairs(rest[key]) do
                    kids[#kids + 1] = row(e.a, e.host, nil, open)
                end

                item:subscribe("mouse.clicked", function()
                    open = not open
                    expanded[key] = open
                    item:set({ icon = { string = open and "▾" or "▸" } })
                    for _, kid in ipairs(kids) do kid:set({ drawing = open }) end
                end)
                -- These are the only popup items taking mouse events rather than a
                -- click_script, so they capture the global exit the chip used to get.
                item:subscribe("mouse.exited.global", function()
                    chip:set({ popup = { drawing = false } })
                end)
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

    -- The snapshot rather than `agent list`: it carries the tabs alongside the agents, so
    -- their names cost no extra round trip — which over ssh is the whole cost.
    local function poll_host(host)
        sbar.exec(host_cmd(host, "api snapshot"), function(result)
            local snap = type(result) == "table" and result.result and result.result.snapshot
            if snap and snap.agents then
                fleet[host.name] = snap.agents
                local labels = {}
                for _, tab in ipairs(snap.tabs or {}) do labels[tab.tab_id] = tab.label end
                tab_labels[host.name] = labels
                offline[host.name] = nil
            else
                -- Dropped rather than kept: a host that stops answering would otherwise nag
                -- about a block that ended long ago, and a stuck alert is worse than a late one.
                fleet[host.name] = {}
                if host.machine then offline[host.name] = true end
            end
            render_chip()
        end)
    end

    -- Re-read on every remote sweep so a machine added or disabled shows up without a reload.
    local function poll_machines()
        sbar.exec("herdr machine list --json 2>/dev/null", function(list)
            local next_hosts, seen = { hosts[1] }, {}
            for _, m in ipairs(type(list) == "table" and list or {}) do
                if m.enabled and m.id then
                    local name = m.label or m.id
                    seen[name] = true
                    next_hosts[#next_hosts + 1] = { name = name, machine = m.id }
                end
            end
            for name in pairs(fleet) do
                if name ~= "local" and not seen[name] then fleet[name], offline[name] = nil, nil end
            end
            hosts = next_hosts
            for i = 2, #hosts do poll_host(hosts[i]) end
        end)
    end

    local function poll()
        poll_host(hosts[1])
    end

    -- A remote snapshot is a whole ssh round trip (~2s), so machines run on their own
    -- slower cadence, counted off the chip's routine rather than a second timer item.
    local every = math.max(1, math.floor((conf.remote_poll or 15) / (conf.poll or 5)))
    local ticks = 0

    chip:subscribe("routine", function()
        poll()
        ticks = ticks + 1
        if ticks % every == 0 then poll_machines() end
    end)
    chip:subscribe("forced", poll)
    chip:subscribe("mouse.clicked", function()
        render_popup()
        chip:set({ popup = { drawing = "toggle" } })
    end)
    chip:subscribe("mouse.exited.global", function()
        chip:set({ popup = { drawing = false } })
    end)

    sbar.add("event", "herdr_render")
    chip:subscribe("herdr_render", render_popup)

    poll()
    poll_machines()
end

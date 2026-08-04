return function(ctx)
    ctx.owns_popup()
    local p = ctx.palette
    local conf = type(ctx.config.herdr) == "table" and ctx.config.herdr or {}
    local fixed, follows = ctx.host_of(conf)
    local target = fixed or (follows and ((ctx.config.servers or {}).default or "local")) or nil
    local fleet, tab_labels = {}, {}

    -- A target collapses the fleet to one host; untargeted, the configured list stands.
    local function resolve()
        if not target then return conf.hosts or { { name = "local" } } end
        if target == "local" then return { { name = "local" } } end
        return { { name = target, ssh = target } }
    end
    local hosts = resolve()

    -- Watched whichever host the chip is showing, since an agent waiting on a server you
    -- are not looking at is the one you would miss. Read on every call, not once: the
    -- servers widget loads after this one, so its aliases do not exist yet here.
    local blocked_away = {}
    local function watched()
        -- Untargeted, every configured host is already on the chip and in the popup.
        if not target or not conf.watch then return {} end
        local aliases = conf.watch
        if aliases == true then
            -- Named outright because the servers list only carries "local" in selector
            -- mode, and select a server and the agents waiting here are what go quiet.
            aliases = { "local" }
            for _, h in ipairs(ctx.server_hosts or {}) do
                if h.alias ~= "local" then aliases[#aliases + 1] = h.alias end
            end
        end
        local out = {}
        for _, alias in ipairs(aliases) do
            -- No ssh field means run herdr here, which is what host_cmd branches on.
            if alias ~= target then
                out[#out + 1] = { name = alias, ssh = alias ~= "local" and alias or nil }
            end
        end
        return out
    end

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

    -- string.format, never `..`: concatenation drops an operand and builds
    -- `-o ConnectTimeout=4'host'`, which ssh rejects with empty stdout.
    local function over_ssh(host, args)
        return string.format("%s %s %s", ctx.shell_quote(ctx.helper("herdr_remote.sh")),
            ctx.shell_quote(host.ssh), args)
    end

    local function host_cmd(host, args)
        if host.ssh then
            return string.format("%s 2>/dev/null", over_ssh(host, args))
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
        for alias, n in pairs(blocked_away) do
            if alias ~= target then blocked = blocked + n end
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
        for _, host in ipairs(watched()) do
            parts[#parts + 1] = string.format("%s=%d", host.name, blocked_away[host.name] or 0)
        end
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
            -- A remote pane has no local window to raise, so clicking one brings the
            -- session here instead of only moving focus on the far side.
            local focus = host.ssh
                and string.format("%s %s %s", ctx.shell_quote(ctx.helper("herdr_attach.sh")),
                    ctx.shell_quote(host.ssh), ctx.shell_quote(a.pane_id))
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

        -- Hosts the chip is not showing. A count is the whole message — the agents behind
        -- it are a poll away on the far side — so clicking retargets the bar to go look.
        local away = {}
        for _, h in ipairs(watched()) do
            local blocked = blocked_away[h.name] or 0
            if blocked > 0 then away[#away + 1] = { host = h, blocked = blocked } end
        end
        if #away > 0 then
            local sum = 0
            for _, e in ipairs(away) do sum = sum + e.blocked end
            section("needs you elsewhere", sum, p.bad)
            for _, e in ipairs(away) do
                n = n + 1
                sbar.add("item", "herdr.row." .. n, {
                    position = "popup." .. chip.name,
                    icon = { string = "◆", color = p.bad, font = { size = 9.0 },
                        padding_left = 12, padding_right = 7 },
                    label = {
                        string = string.format("%s   %d", e.host.name, e.blocked),
                        color = p.fg,
                        font = { size = 11.0 },
                        padding_left = 0,
                        padding_right = 14,
                    },
                    background = { color = ctx.with_alpha(p.bad, 0.17),
                        corner_radius = 6, height = 20 },
                    -- Retargeting is the servers picker's job, and herdr only listens to it
                    -- while it follows: pinned to one host, the row has nowhere to send you.
                    click_script = follows and string.format(
                        "sketchybar --set herdr popup.drawing=off --trigger host_change HOST=%s",
                        ctx.shell_quote(e.host.name)) or nil,
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

    -- A reply from the host we just left would land after the reset and be counted into
    -- the new one. Bumped only on retarget, so a slow reply from the current host still lands.
    local epoch = 0

    -- The snapshot rather than `agent list`: it carries the tabs alongside the agents, so
    -- their names cost no extra round trip — which over ssh is the whole cost.
    local function poll()
        local mine = epoch
        for _, host in ipairs(hosts) do
            sbar.exec(host_cmd(host, "api snapshot"), function(result)
                if mine ~= epoch then return end
                local snap = type(result) == "table" and result.result and result.result.snapshot
                if snap and snap.agents then
                    fleet[host.name] = snap.agents
                    local labels = {}
                    for _, tab in ipairs(snap.tabs or {}) do labels[tab.tab_id] = tab.label end
                    tab_labels[host.name] = labels
                elseif not host.ssh then
                    fleet[host.name] = {}
                end
                render_chip()
            end)
        end
    end

    -- A watched host costs a whole ssh round trip, so it runs on its own slower cadence,
    -- counted off the chip's routine rather than paying for a second timer item.
    local function poll_away()
        for _, host in ipairs(watched()) do
            local alias, mine = host.name, epoch
            -- `agent list`, not the snapshot: a watched host only contributes a count.
            sbar.exec(host_cmd(host, "agent list"), function(result)
                if mine ~= epoch then return end
                -- A reply that parsed to nothing counts as zero rather than being skipped.
                -- Keeping the last number would let a host that stops answering — ssh
                -- down, herdr restarted, a reply too slow for the poll — nag about a block
                -- that ended long ago, and a stuck alert is worse than a late one.
                local agents = type(result) == "table" and result.result
                    and result.result.agents or {}
                local blocked = 0
                for _, a in ipairs(agents) do
                    if a.agent_status == "blocked" then blocked = blocked + 1 end
                end
                blocked_away[alias] = blocked
                render_chip()
            end)
        end
    end

    local every = math.max(1, math.floor((conf.watch_poll or 30) / (conf.poll or 5)))
    -- One short of the cadence, so the first sweep lands on the next tick instead of a
    -- full watch_poll after a reload. Not here: the servers widget has not loaded yet.
    local ticks = every - 1

    chip:subscribe("routine", function()
        poll()
        ticks = ticks + 1
        if ticks % every == 0 then poll_away() end
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

    if follows then
        sbar.add("event", "host_change")
        chip:subscribe("host_change", function(env)
            if not env.HOST or env.HOST == "" or env.HOST == target then return end
            target = env.HOST
            hosts = resolve()
            fleet, tab_labels = {}, {}
            -- Counts freeze the moment a host stops being watched, so the host you just
            -- came back from still claims whatever it claimed when you left it — which is
            -- exactly the block you went there to clear. Drop them and ask again.
            blocked_away = {}
            epoch = epoch + 1
            poll()
            poll_away()
        end)
    end
    poll()
end

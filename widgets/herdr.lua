return function(ctx)
    ctx.owns_popup()
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

    -- string.format, never `..`: concatenation drops an operand and builds
    -- `-o ConnectTimeout=4'host'`, which ssh rejects with empty stdout.
    local function over_ssh(host, args)
        return string.format("%s %s %s", ctx.shell_quote(ctx.helper("herdr_remote.sh")),
            ctx.shell_quote(host.ssh), args)
    end

    local function host_cmd(host)
        if host.ssh then
            return string.format("%s 2>/dev/null", over_ssh(host, "agent list"))
        end
        return "herdr agent list 2>/dev/null"
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
        if total == 0 then
            chip:set({ drawing = false })
            backdrop:set({ drawing = false })
            return
        end
        -- One number, coloured. U+26A1 and the alert glyph both fall back off
        -- JetBrainsMono and render oversized on their own baseline; at this size the
        -- colour carries the state anyway and the popup has the breakdown.
        local count, color = total, ctx.with_alpha(p.fg, 0.7)
        if blocked > 0 then
            count, color = blocked, p.bad
        elseif working > 0 then
            count, color = working, p.accent
        end

        backdrop:set({ drawing = true })
        chip:set({
            drawing = true,
            icon = { string = glyph_of(lead and lead.agent), color = color },
            label = { string = tostring(count), color = color },
        })
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

    -- "π - tracing" beside a "tracing" heading says nothing twice; only then fall back to
    -- the pane, which is all that distinguishes sibling agents in one project.
    local function row_text(a)
        local title = a.terminal_title_stripped or a.terminal_title or ""
        local tail = title:match("^%S+%s+%-%s+(.+)$")
        if title == "" or tail == leaf_of(a) then
            return (a.pane_id or ""):match("[^:]+$") or "?"
        end
        return clip(title, 38)
    end

    local function render_popup()
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
                        row_text(a), suffix or ""),
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

    sbar.add("event", "herdr_render")
    chip:subscribe("herdr_render", render_popup)

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

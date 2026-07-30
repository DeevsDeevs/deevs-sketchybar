-- Enumerate Host aliases: `ssh -G` cannot list what exists, so Include'd files
-- (relative paths glob against ~/.ssh) are scanned too; `Host=alias` is legal, hence the `=` fixup.
local DISCOVER = [[cd "$HOME/.ssh" 2>/dev/null || exit 0
[ -r config ] || exit 0
K='{ l=$0; sub(/^[ \t]+/,"",l); if (l ~ /^[A-Za-z]+=/) sub(/=/," ",l); n=split(l,f);
     if (tolower(f[1])==k) for (i=2;i<=n;i++) { v=f[i];
       if (k=="include") sub(/^~\//,ENVIRON["HOME"] "/",v); print v } }'
awk -v k=host "$K" config $(awk -v k=include "$K" config) 2>/dev/null]]

-- `ssh -G` resolves config only, no socket; run concurrently to keep load fast.
-- Presence of proxyjump/proxycommand marks a jump-only host: drop it, probing its private address is meaningless.
local RESOLVE = [[ | awk '!s[$0]++' | { n=0
while IFS= read -r a; do
  case $a in ''|*[*?]*) continue ;; esac
  n=$((n+1))
  ( ssh -G -- "$a" 2>/dev/null | awk -v n="$n" -v a="$a" '
      $1=="hostname"{h=$2} $1=="port"{p=$2}
      $1=="proxyjump"||$1=="proxycommand"{x=1}
      END{ if (h!="" && !x) print n"\t"a"\t"h"\t"(p==""?22:p) }' ) &
done
wait
} | sort -n]]

return function(ctx)
    local p = ctx.palette
    local cfg = ctx.config.servers or {}
    local idle = ctx.with_alpha(p.fg, 0.25)

    -- Explicit `hosts` replaces discovery. Only strings count, so the old
    -- `hosts = { { name, host } }` schema falls through to discovery instead of quoting a table address.
    local quoted = {}
    for _, alias in ipairs(type(cfg.hosts) == "table" and cfg.hosts or {}) do
        if type(alias) == "string" and alias ~= "" then
            quoted[#quoted + 1] = ctx.shell_quote(alias)
        end
    end
    local source, filter = DISCOVER, cfg.filter
    if #quoted > 0 then
        source, filter = "printf '%s\\n' " .. table.concat(quoted, " "), nil
    end

    -- Synchronous: the bracket is built the moment this returns, so an async reply could not add dots later.
    local hosts = {}
    local pipe = io.popen(source .. RESOLVE, "r")
    if pipe then
        for line in pipe:read("a"):gmatch("[^\n]+") do
            local alias, host, port = line:match("^%d+\t([^\t]+)\t([^\t]+)\t(%d+)$")
            local keep = alias ~= nil
            if keep and filter then
                -- pcall: a bad `filter` pattern must not abort the whole config load.
                local ok, found = pcall(string.find, alias, filter)
                keep = ok and found ~= nil
            end
            if keep then
                hosts[#hosts + 1] = { alias = alias, addr = host, port = tonumber(port) or 22 }
            end
        end
        pipe:close()
    end
    if #hosts == 0 then return end

    -- Right-position items lay out right-to-left in creation order: dots reversed, icon last to sit leftmost.
    local dots, rows = {}, {}
    for i = #hosts, 1, -1 do
        dots[i] = sbar.add("item", "widgets.servers.dot." .. i, {
            position = "right",
            icon = { string = "\u{f0765}", font = { size = 9.0 }, color = idle },
            label = { drawing = false },
            padding_left = 1,
            padding_right = 1,
        })
        table.insert(ctx.groups.right, dots[i].name)
        ctx.cluster("servers", dots[i].name)
    end

    local servers = sbar.add("item", "widgets.servers", {
        position = "right",
        icon = { string = "\u{f048d}", font = { size = 12.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = { drawing = false },
        update_freq = 60,
        popup = { align = "center" },
    })
    table.insert(ctx.groups.right, servers.name)
    ctx.cluster("servers", servers.name)

    -- JetBrainsMono advances ~7.8px/char at 13px; size to the longest alias so names never clip.
    local longest = 0
    for _, h in ipairs(hosts) do longest = math.max(longest, #h.alias) end
    local name_width = math.max(90, math.ceil(longest * 7.8) + 8)

    -- Alias only, never the resolved hostname: a 48-char EC2 name would triple the popup width.
    for i, h in ipairs(hosts) do
        rows[i] = sbar.add("item", "widgets.servers.row." .. i, {
            position = "popup." .. servers.name,
            icon = { string = h.alias, width = name_width, align = "left" },
            label = { string = "···", width = 50, align = "right", color = idle },
        })
    end

    -- Parallel probes: SbarLua's exec child carries alarm(60) — a sequential sweep past 60s is
    -- killed and the callback never fires. Each line carries its host index since replies finish in any order.
    local probes = {}
    for i, h in ipairs(hosts) do
        -- Only -G bounds the connect: `nc -z -w 3` against a black-holed address takes 75s.
        probes[i] = "( nc -z -G 3 " .. ctx.shell_quote(h.addr) .. " " .. h.port
            .. " >/dev/null 2>&1 && echo '" .. i .. " 1' || echo '" .. i .. " 0' ) &"
    end
    local probe = table.concat(probes, " ") .. " wait"

    local function paint(i, up)
        dots[i]:set({ icon = { color = up and p.good or p.bad } })
        rows[i]:set({ label = { string = up and "up" or "down",
            color = up and p.good or p.bad } })
    end

    local function apply(out)
        local seen = {}
        -- Anchored per-line match: the exec response reaches lua un-NUL-terminated,
        -- so the tail can carry garbage that a loose scan would count as state.
        for line in tostring(out):gmatch("[^\n]+") do
            local index, state = line:match("^(%d+) ([01])$")
            local i = index and tonumber(index)
            if i and hosts[i] then
                seen[i] = true
                paint(i, state == "1")
            end
        end
        -- A missing line reverts to unknown rather than holding a stale colour.
        for i = 1, #hosts do
            if not seen[i] then
                dots[i]:set({ icon = { color = idle } })
                rows[i]:set({ label = { string = "···", color = idle } })
            end
        end
    end

    local function refresh() sbar.exec(probe, apply) end

    servers:subscribe({ "routine", "forced", "system_woke" }, refresh)
    -- routine first fires only after update_freq; prime immediately.
    refresh()

    servers:subscribe("mouse.clicked", function()
        servers:set({ popup = { drawing = "toggle" } })
        refresh()
    end)
    servers:subscribe("mouse.exited.global", function()
        servers:set({ popup = { drawing = false } })
    end)
end

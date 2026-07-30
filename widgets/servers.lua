-- `ssh -G` cannot list what Host aliases exist, so scan config plus Include'd files (relative paths glob against ~/.ssh); `Host=alias` is legal, hence the `=` fixup.
local DISCOVER = [[cd "$HOME/.ssh" 2>/dev/null || exit 0
[ -r config ] || exit 0
K='{ l=$0; sub(/^[ \t]+/,"",l); if (l ~ /^[A-Za-z]+=/) sub(/=/," ",l); n=split(l,f);
     if (tolower(f[1])==k) for (i=2;i<=n;i++) { v=f[i];
       if (k=="include") sub(/^~\//,ENVIRON["HOME"] "/",v); print v } }'
awk -v k=host "$K" config $(awk -v k=include "$K" config) 2>/dev/null]]

-- proxyjump/proxycommand marks a jump-only host: drop it, probing its private address is meaningless.
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

    for i, h in ipairs(hosts) do
        rows[i] = sbar.add("item", "widgets.servers.row." .. i, {
            position = "popup." .. servers.name,
            icon = { string = h.alias, width = name_width, align = "left" },
            label = { string = "···", width = 50, align = "right", color = idle },
        })
    end

    -- Parallel: SbarLua's exec child carries alarm(60), so a sequential sweep past 60s is killed and the callback never fires.
    local probes = {}
    for i, h in ipairs(hosts) do
        -- Only nc -G bounds the connect: -w 3 against a black-holed address takes 75s.
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
        -- The exec response arrives un-NUL-terminated; anchored per-line match rejects the garbage tail.
        for line in tostring(out):gmatch("[^\n]+") do
            local index, state = line:match("^(%d+) ([01])$")
            local i = index and tonumber(index)
            if i and hosts[i] then
                seen[i] = true
                paint(i, state == "1")
            end
        end
        for i = 1, #hosts do
            if not seen[i] then
                dots[i]:set({ icon = { color = idle } })
                rows[i]:set({ label = { string = "···", color = idle } })
            end
        end
    end

    local function refresh() sbar.exec(probe, apply) end

    servers:subscribe({ "routine", "forced", "system_woke" }, refresh)
    refresh()

    servers:subscribe("mouse.clicked", function()
        servers:set({ popup = { drawing = "toggle" } })
        refresh()
    end)
    servers:subscribe("mouse.exited.global", function()
        servers:set({ popup = { drawing = false } })
    end)
end

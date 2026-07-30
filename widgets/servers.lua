-- Enumerate the Host aliases. Kept separate from resolution because `ssh -G`
-- follows Include for the host it is asked about but cannot list what exists,
-- and a top-level-only scan silently misses whole files (Include
-- ~/.orbstack/ssh/config is a common one). Relative Include paths glob against
-- ~/.ssh, which is what ssh itself does. `Host=alias` is as legal as
-- `Host alias`, hence the `=` fixup.
local DISCOVER = [[cd "$HOME/.ssh" 2>/dev/null || exit 0
[ -r config ] || exit 0
K='{ l=$0; sub(/^[ \t]+/,"",l); if (l ~ /^[A-Za-z]+=/) sub(/=/," ",l); n=split(l,f);
     if (tolower(f[1])==k) for (i=2;i<=n;i++) { v=f[i];
       if (k=="include") sub(/^~\//,ENVIRON["HOME"] "/",v); print v } }'
awk -v k=host "$K" config $(awk -v k=include "$K" config) 2>/dev/null]]

-- `ssh -G` is pure config resolution: it applies Match blocks, follows Include
-- and trims the stray whitespace people leave after a HostName, without opening
-- a socket (measured at 25ms per alias, no network). Resolving concurrently
-- keeps a forty-host config off the critical path at load.
-- proxyjump/proxycommand are absent from the output rather than empty when
-- unset, so their mere presence marks a host as reachable only through a jump —
-- and a direct probe of such a host's private address is a permanent red dot
-- that says nothing, so those are dropped instead of guessed at.
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

    -- Precedence: an explicit `hosts` list of aliases replaces discovery
    -- outright, else every non-wildcard alias in the ssh config, narrowed by
    -- `filter`. Only strings count as aliases, so the older
    -- `hosts = { { name, host } }` schema falls through to discovery rather than
    -- shell-quoting a table address into a dot.
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

    -- Read synchronously: the number of dots is decided here, and the bracket
    -- around them is built the moment this function returns, so there is no
    -- later point at which an async reply could still add items.
    local hosts = {}
    local pipe = io.popen(source .. RESOLVE, "r")
    if pipe then
        for line in pipe:read("a"):gmatch("[^\n]+") do
            local alias, host, port = line:match("^%d+\t([^\t]+)\t([^\t]+)\t(%d+)$")
            local keep = alias ~= nil
            if keep and filter then
                -- A bad pattern in config.lua would otherwise abort the config
                -- load here and take every later widget down with it.
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

    -- Right-position items lay out right-to-left in creation order, so the dots
    -- go in reverse and the icon last to end up leftmost.
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

    -- JetBrainsMono advances 0.6em, so a name costs 7.8px per character at the
    -- popup's 13px icon size. Aliases are the long part of an ssh config
    -- (deevs.hetzner.whitecircle is 25 characters, 203px) and a clipped name
    -- defeats the only thing the popup is here to say.
    local longest = 0
    for _, h in ipairs(hosts) do longest = math.max(longest, #h.alias) end
    local name_width = math.max(90, math.ceil(longest * 7.8) + 8)

    -- The alias, not the resolved hostname: it is what the user types and what
    -- their ssh config is organised by. The hostname is deliberately left out —
    -- one of these resolves to a 48-character EC2 name and would triple the
    -- popup width to restate what the alias already identifies.
    for i, h in ipairs(hosts) do
        rows[i] = sbar.add("item", "widgets.servers.row." .. i, {
            position = "popup." .. servers.name,
            icon = { string = h.alias, width = name_width, align = "left" },
            label = { string = "···", width = 50, align = "right", color = idle },
        })
    end

    -- Probes run concurrently. Sequentially, N hosts behind a firewall cost
    -- 3s each, and SbarLua puts alarm(60) on the child it forks for an exec —
    -- past 60s of sweep the child is killed and the callback never fires at
    -- all, so the dots would freeze rather than go stale visibly. In parallel
    -- the sweep costs one timeout no matter how long the fleet is.
    -- Each line carries its host index because concurrent probes finish in any
    -- order.
    local probes = {}
    for i, h in ipairs(hosts) do
        -- Only -G bounds the connect. -w is documented as a timeout but does
        -- not apply to -z's connect: `nc -z -w 3` against a black-holed
        -- address takes 75s, `nc -z -G 3` takes 3s.
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
        -- Matched line by line and anchored at both ends, so anything that is
        -- not exactly "<index> <0|1>" is dropped instead of being counted as a
        -- state. A loose scan for [01] shifts every host after any stray digit,
        -- and the exec response reaches lua without a terminator, so a garbage
        -- tail on the last line is a real possibility.
        for line in tostring(out):gmatch("[^\n]+") do
            local index, state = line:match("^(%d+) ([01])$")
            local i = index and tonumber(index)
            if i and hosts[i] then
                seen[i] = true
                paint(i, state == "1")
            end
        end
        -- A host whose line went missing reverts to unknown. Holding the last
        -- sweep's colour would report a stale up as current.
        for i = 1, #hosts do
            if not seen[i] then
                dots[i]:set({ icon = { color = idle } })
                rows[i]:set({ label = { string = "···", color = idle } })
            end
        end
    end

    local function refresh() sbar.exec(probe, apply) end

    servers:subscribe({ "routine", "forced", "system_woke" }, refresh)
    -- routine does not fire until update_freq has elapsed, which would leave
    -- every dot unknown for the first minute after a reload.
    refresh()

    servers:subscribe("mouse.clicked", function()
        servers:set({ popup = { drawing = "toggle" } })
        refresh()
    end)
    servers:subscribe("mouse.exited.global", function()
        servers:set({ popup = { drawing = false } })
    end)
end

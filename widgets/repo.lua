-- repo sense: the git repo you are working in — name, branch, dirty count, and
-- an optional CI dot from the latest GitHub Actions run on that branch.
-- Follows the focused shell: a zsh chpwd/precmd hook pushes the cwd with
--   sketchybar --trigger repo_cwd RPATH="$PWD"
-- Setting `path` pins the chip to one repo instead and ignores the shell.
return function(ctx)
    local p = ctx.palette
    -- `repo = true` is as valid as a table (see widgets/init.lua), so never
    -- index the config block without checking it is one.
    local cfg = type(ctx.config.repo) == "table" and ctx.config.repo or {}

    local BRANCH_GLYPH, COMMIT_GLYPH, DOT = "\u{e725}", "\u{e729}", "\u{f0765}"
    -- Bounds the label at roughly 36 codepoints: the chip follows you between
    -- repos, so a long name and a long branch must not push the bar around.
    local NAME_MAX, BRANCH_MAX = 12, 14
    local CI_FLOOR = 10 -- burst guard on gh; the real cadence is ci's update_freq

    -- Not every non-success is a failure: a skipped or cancelled run says
    -- nothing about the code, so it reads as unknown rather than red.
    local VERDICT = {
        success   = p.good,
        skipped   = ctx.with_alpha(p.fg, 0.35),
        neutral   = ctx.with_alpha(p.fg, 0.35),
        cancelled = ctx.with_alpha(p.fg, 0.35),
    }

    -- Only `~` and `~/…`. `~otheruser` is a shell feature we would corrupt, and
    -- substituting $HOME through gsub would additionally have to escape any %.
    local function expand(path)
        local home = os.getenv("HOME")
        if not home then return path end
        if path == "~" then return home end
        return path:sub(1, 2) == "~/" and (home .. path:sub(2)) or path
    end

    local pinned = cfg.path and expand(cfg.path) or nil

    -- io.popen inherits exactly the environment sbar.exec's own popen gets, so
    -- a tool found here is a tool the callbacks can actually run.
    local function have(tool)
        local f = io.popen("command -v " .. tool .. " 2>/dev/null")
        local found = (f and f:read("*a") or "") ~= ""
        if f then f:close() end
        return found
    end

    -- Clip by codepoint: a byte sub cuts a multibyte character in half and
    -- renders a replacement glyph.
    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and (str:sub(1, cut - 1) .. "…") or str
    end

    -- SbarLua pushes the child's stdout with lua_pushstring over a buffer it
    -- never NUL-terminates, so a read can carry whatever followed it in memory.
    -- Every command here ends in a newline, so the first line is the safe part.
    local function first_line(out)
        local str = tostring(out or ""):match("[^\r\n]+") or ""
        return (str:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- The git query lives in helpers/repo_state.sh, like every other non-trivial
    -- shell command here.

    -- Created before the text item, so it lands to the right of it.
    local ci
    if cfg.ci and have("gh") then
        ci = sbar.add("item", "widgets.repo.ci", {
            position = "right",
            icon = { string = DOT, font = { size = 9.0 }, color = ctx.with_alpha(p.fg, 0.25) },
            label = { drawing = false },
            padding_left = 2,
            drawing = false,
            updates = true, -- a hidden item gets no routine, so it could never come back
            update_freq = 300,
        })
        table.insert(ctx.groups.right, ci.name)
        ctx.cluster("repo", ci.name)
    end

    -- The dirty count also moves when an editor writes or a rebase runs in
    -- another tab, neither of which fires the shell hook, so a routine floor
    -- stays; 15s is live enough and far below the rate that starves callbacks.
    local repo = sbar.add("item", "widgets.repo", {
        position = "right",
        icon = { string = BRANCH_GLYPH, font = { size = 12.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = { string = "—", color = ctx.with_alpha(p.fg, 0.8) },
        update_freq = 15,
        updates = true,
    })
    table.insert(ctx.groups.right, repo.name)
    ctx.cluster("repo", repo.name)

    local root, name, branch, sha, dirty
    local here = true  -- is the shell's reported cwd inside `root`
    local misses = 0
    local seen_cwd, seen_at = nil, 0
    local ci_key, ci_at = "", 0
    local paint, refresh, poll, ci_fetch, ci_track

    paint = function()
        if not root then
            return repo:set({
                icon = { string = BRANCH_GLYPH, color = ctx.with_alpha(p.fg, 0.3) },
                label = { string = "—", color = ctx.with_alpha(p.fg, 0.4) },
            })
        end
        local text = clip(name, NAME_MAX) .. " " .. (branch and clip(branch, BRANCH_MAX) or sha or "?")
        if (dirty or 0) > 0 then text = text .. " ±" .. dirty end
        repo:set({
            -- Detached HEAD is normal (mid-rebase, a checked-out tag) and has no
            -- branch name, so it shows the short SHA under a commit glyph.
            -- Away from the repo the chip is a memory rather than a location:
            -- dimming says so without the reflow that hiding it would cause.
            icon = { string = branch and BRANCH_GLYPH or COMMIT_GLYPH,
                     color = ctx.with_alpha(p.fg, here and 0.7 or 0.3) },
            label = { string = text, color = ctx.with_alpha(p.fg, here and 0.9 or 0.45) },
        })
    end

    -- One exec answers root, branch, commit and dirty count together, for one
    -- directory. Two separate calls were not just wasteful: SbarLua recycles its
    -- exec callback refs, so with several in flight a reply can be delivered to
    -- another exec's callback — measured, a rev-parse for one repo handed back a
    -- different repo's path. The helper echoes the directory it was asked about
    -- and anything that does not match what we asked is dropped, so a crossed
    -- reply is inert instead of wrong.
    poll = function(dir)
        if not dir then return end
        sbar.exec(string.format("%s %s",
            ctx.shell_quote(ctx.helper("repo_state.sh")),
            ctx.shell_quote(dir)), function(out)
            local verdict, asked, rest = first_line(out):match("^(%a+)\t([^\t]*)\t?(.*)$")
            if asked ~= dir then return end -- not our reply

            if verdict == "no" then
                -- Not a repo. Hold the repo we already had and dim it, rather
                -- than reflowing the bar on every cd to ~.
                here = false
                return paint()
            end

            local top, head, oid, count = rest:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)$")
            if not top then
                -- One bad read is usually contention (an index.lock mid-rebase),
                -- not a lost repo; only a repeated one retires the chip.
                misses = misses + 1
                if misses < 3 then return end
                root, name, branch, sha, dirty = nil, nil, nil, nil, nil
                return paint()
            end

            here, misses = true, 0
            if top ~= root then
                root, name = top, top:match("([^/]+)/*$") or top
            end
            branch = head ~= "(detached)" and head or nil
            sha = oid:match("^%x+$") and oid or nil -- "(initial)" before the first commit
            dirty = tonumber(count)
            paint()
            ci_track()
        end)
    end

    -- Routine re-asks about the directory last reported, so a change made by an
    -- editor or a rebase in another tab still shows up without the shell moving.
    refresh = function() poll(pinned or seen_cwd or root) end

    -- Detached HEAD has no branch to ask about, and an unfiltered run list would
    -- answer for whichever branch ran last rather than for this checkout.
    ci_fetch = function()
        if not (ci and root and branch) then return end
        if os.time() - ci_at < CI_FLOOR then return end
        ci_at = os.time()
        -- gh has no -C, so cd. </dev/null because gh prompts if it thinks it has
        -- a terminal, and a child blocked for its alarm(60) is worse than a
        -- missing colour.
        sbar.exec(string.format(
            "cd %s && gh run list --branch %s --limit 1 --json status,conclusion </dev/null 2>/dev/null",
            ctx.shell_quote(root), ctx.shell_quote(branch)), function(out)
            -- Array/object stdout arrives already parsed into a table. gh prints
            -- nothing at all when there is no GitHub remote, no run on this
            -- branch, or no credentials, and none may inherit the last colour.
            local run = type(out) == "table" and out[1] or nil
            local status = type(run) == "table" and run.status or nil
            if type(status) ~= "string" then
                return ci:set({ drawing = false, update_freq = 300 })
            end
            local conclusion = type(run.conclusion) == "string" and run.conclusion or nil
            local running = status ~= "completed"
            ci:set({
                drawing = true,
                -- Only spin the timer while a run is actually in flight.
                update_freq = running and 60 or 300,
                icon = { color = running and p.warn or (VERDICT[conclusion] or p.bad) },
            })
        end)
    end

    ci_track = function()
        if not ci then return end
        local key = (root or "") .. "\n" .. (branch or "")
        if key == ci_key then return end
        ci_key = key
        -- A verdict belongs to one repo+branch; carrying the colour across a
        -- switch would show the last repo's result beside the new name. Poll
        -- faster until the new one has an answer, in case the burst guard
        -- swallowed this fetch.
        ci:set({ drawing = false, update_freq = 60 })
        ci_fetch()
    end

    -- Checked against sketchybar's own event table: repo_cwd is not one of the
    -- built-in names, so triggers on it are delivered. A reserved name is
    -- silently swallowed instead — that is why media uses media_update.
    sbar.add("event", "repo_cwd")

    repo:subscribe({ "routine", "forced", "system_woke" }, refresh)
    -- The dot keeps its own slower clock: the branch it reports on only changes
    -- when the status read says so, and every tick of this one is a network call.
    if ci then ci:subscribe({ "routine", "forced", "system_woke" }, ci_fetch) end

    if not pinned then
        repo:subscribe("repo_cwd", function(env)
            local cwd = first_line(env.RPATH)
            if cwd == "" then return end
            if cwd ~= seen_cwd then
                seen_cwd, seen_at = cwd, os.time()
                return poll(cwd)
            end
            -- Same directory, prompt fired again (a commit, a build). precmd
            -- fires on every bare Enter, hence the floor.
            if os.time() - seen_at < 1 then return end
            seen_at = os.time()
            poll(cwd)
        end)
    end

    -- Routine is up to update_freq away, so a pinned repo would otherwise sit
    -- on "—" after every reload.
    if pinned then poll(pinned) end
end

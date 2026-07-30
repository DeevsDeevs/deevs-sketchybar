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
    -- JetBrainsMono advances 0.6em, so the 118px box holds ~17 characters at 11px
    -- and ~21 at 9px. The chip follows you between repos, so neither line may
    -- push the bar around.
    local NAME_MAX, BRANCH_MAX = 20, 17

    -- A branch's meaning is in its tail, and the type prefix carries almost none
    -- of it: `fix/artifact-d…` says nothing where `artifact…timeout` says a lot.
    local TYPE_PREFIX = { "feature/", "refactor/", "release/", "hotfix/",
                          "bugfix/", "chore/", "feat/", "docs/", "test/", "fix/" }
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
        return cut and string.format("%s…", str:sub(1, cut - 1)) or str
    end

    -- Ellipsis in the middle, keeping both ends.
    local function middle_clip(value, limit)
        local str = tostring(value or "")
        local len = utf8.len(str) or #str
        if len <= limit or limit < 3 then return clip(value, limit) end
        local head = (limit - 1) // 2
        local tail = limit - 1 - head
        local a = utf8.offset(str, head + 1) or 1
        local b = utf8.offset(str, len - tail + 1) or 1
        -- Don't strand a separator against the ellipsis ("artifact…-timeout").
        return string.format("%s…%s",
            (str:sub(1, a - 1):gsub("[-_/%.]+$", "")),
            (str:sub(b):gsub("^[-_/%.]+", "")))
    end

    local function short_branch(value, limit)
        local str = tostring(value or "")
        local lower = str:lower()
        for _, prefix in ipairs(TYPE_PREFIX) do
            if lower:sub(1, #prefix) == prefix then
                str = str:sub(#prefix + 1)
                break
            end
        end
        return middle_clip(str, limit)
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

    -- Two-line stack, same construction as the media widget: the repo name sits
    -- above the branch. They share one box only because both labels carry the
    -- SAME fixed width — width = 0 on the item does not collapse the upper line,
    -- it just parks it beside the lower one at a different height, which reads as
    -- two ragged lines. The upper line is created first so it is the zero-width
    -- overlay sitting on top.
    local TEXT_W = 118

    -- The dirty count also moves when an editor writes or a rebase runs in
    -- another tab, neither of which fires the shell hook, so a routine floor
    -- stays; 15s is live enough and far below the rate that starves callbacks.
    local top_line = sbar.add("item", "widgets.repo.name", {
        position = "right",
        width = 0,
        updates = true,
        padding_left = 0,
        padding_right = 0,
        icon = { drawing = false },
        label = {
            string = "", width = TEXT_W, align = "left",
            font = { size = 9.0 }, color = ctx.with_alpha(p.fg, 0.5),
            padding_left = 0, padding_right = 0, y_offset = 6,
        },
    })
    table.insert(ctx.groups.right, top_line.name)
    ctx.cluster("repo", top_line.name)

    local repo = sbar.add("item", "widgets.repo", {
        position = "right",
        icon = { string = BRANCH_GLYPH, font = { size = 12.0 }, color = ctx.with_alpha(p.fg, 0.7) },
        label = {
            string = "—", width = TEXT_W, align = "left",
            font = { size = 11.0 }, color = ctx.with_alpha(p.fg, 0.9),
            y_offset = -5,
        },
        update_freq = 15,
        updates = true,
        popup = { align = "center" },
    })
    table.insert(ctx.groups.right, repo.name)
    ctx.cluster("repo", repo.name)

    -- Popup rows carry the detail the chip has no room for. They join neither
    -- ctx.groups.right nor the cluster: popup children are not bar items.
    local ROWS = { "repo", "branch", "upstream", "changes", "last", "ci" }
    local rows, actions = {}, {}
    for _, key in ipairs(ROWS) do
        rows[key] = sbar.add("item", string.format("widgets.repo.row.%s", key), {
            position = string.format("popup.%s", repo.name),
            icon = { string = key, width = 76, align = "left",
                     color = ctx.with_alpha(p.fg, 0.45) },
            label = { string = "—", width = 300, align = "left" },
        })
        -- Rows act on click. No click_script — an item that has one never
        -- forwards mouse events, and the popup needs mouse.exited.global to close.
        rows[key]:subscribe("mouse.clicked", function()
            repo:set({ popup = { drawing = false } })
            local action = actions[key]
            if action then sbar.exec(action()) end
        end)
    end

    -- $EDITOR rather than a hardcoded editor, and only its first word: the value
    -- may carry flags, and a blocking one ("zeditor --wait") would hold the exec
    -- child until SbarLua's alarm(60) kills it. Falls back to `open`.
    local function in_editor(path)
        return string.format(
            "set -- ${EDITOR:-open}; exec \"$1\" %s >/dev/null 2>&1 &",
            ctx.shell_quote(path))
    end

    local root, name, branch, sha, dirty
    local staged, unstaged, untracked, ahead, behind, upstream, subject
    local here = true  -- is the shell's reported cwd inside `root`
    local misses = 0
    local seen_cwd, seen_at = nil, 0
    local ci_key, ci_at = "", 0
    local ci_text, ci_run = "—", nil
    local paint, refresh, poll, ci_fetch, ci_track, fill

    paint = function()
        if not root then
            top_line:set({ label = { string = "" } })
            return repo:set({
                icon = { string = BRANCH_GLYPH, color = ctx.with_alpha(p.fg, 0.3) },
                label = { string = "—", color = ctx.with_alpha(p.fg, 0.4) },
            })
        end
        -- string.format throughout, never `..`: see ctx.shell_quote in core/init.lua.
        local suffix = (dirty or 0) > 0 and string.format(" ±%d", dirty) or ""
        local lower = branch
            and short_branch(branch, BRANCH_MAX - #suffix)
            or sha or "?"
        -- Away from the repo the chip is a memory rather than a location: dimming
        -- says so without the reflow that hiding it would cause.
        top_line:set({ label = {
            string = clip(name, NAME_MAX),
            color = ctx.with_alpha(p.fg, here and 0.5 or 0.25),
        } })
        repo:set({
            -- Detached HEAD is normal (mid-rebase, a checked-out tag) and has no
            -- branch name, so it shows the short SHA under a commit glyph.
            icon = { string = branch and BRANCH_GLYPH or COMMIT_GLYPH,
                     color = ctx.with_alpha(p.fg, here and 0.7 or 0.3) },
            label = { string = string.format("%s%s", lower, suffix),
                      color = ctx.with_alpha(p.fg, here and 0.9 or 0.45) },
        })
    end

    -- The popup is where the untruncated truth lives, so nothing here is clipped
    -- except the commit subject, which has no natural bound.
    fill = function()
        local function set(key, value, color)
            rows[key]:set({ label = { string = value or "—",
                color = color or ctx.with_alpha(p.fg, 0.9) } })
        end
        set("repo", name)
        set("branch", branch or (sha and string.format("detached at %s", sha)))
        if upstream and upstream ~= "-" then
            set("upstream", string.format("%s   ↑%d ↓%d", upstream, ahead or 0, behind or 0),
                (behind or 0) > 0 and p.warn or nil)
        else
            set("upstream", "none", ctx.with_alpha(p.fg, 0.45))
        end
        if (dirty or 0) == 0 then
            set("changes", "clean", p.good)
        else
            set("changes", string.format("%d staged · %d unstaged · %d untracked",
                staged or 0, unstaged or 0, untracked or 0), p.warn)
        end
        set("last", sha and string.format("%s  %s", sha, clip(subject, 44)))
        set("ci", ci_text)

        -- gh browse and gh run view resolve the remote themselves, so nothing
        -- here has to know the forge URL.
        actions.repo = root and function() return in_editor(root) end or nil
        actions.branch = actions.repo
        actions.changes = actions.repo
        actions.last = (root and sha) and function()
            return string.format("cd %s && gh browse %s </dev/null >/dev/null 2>&1 &",
                ctx.shell_quote(root), ctx.shell_quote(sha))
        end or nil
        -- The branch's tree, not the commit: they are different questions.
        actions.upstream = (root and branch) and function()
            return string.format("cd %s && gh browse --branch %s </dev/null >/dev/null 2>&1 &",
                ctx.shell_quote(root), ctx.shell_quote(branch))
        end or nil
        actions.ci = (root and ci_run) and function()
            return string.format("cd %s && gh run view %d --web </dev/null >/dev/null 2>&1 &",
                ctx.shell_quote(root), ci_run)
        end or nil
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

            local top, head, oid, count, st, un, q, ah, bh, up, subj = rest:match(
                "^([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]*)\t?(.*)$")
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
            staged, unstaged, untracked = tonumber(st), tonumber(un), tonumber(q)
            ahead, behind, upstream, subject = tonumber(ah), tonumber(bh), up, subj
            paint()
            fill()
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
            "cd %s && gh run list --branch %s --limit 1 --json status,conclusion,databaseId </dev/null 2>/dev/null",
            ctx.shell_quote(root), ctx.shell_quote(branch)), function(out)
            -- Array/object stdout arrives already parsed into a table. gh prints
            -- nothing at all when there is no GitHub remote, no run on this
            -- branch, or no credentials, and none may inherit the last colour.
            local run = type(out) == "table" and out[1] or nil
            local status = type(run) == "table" and run.status or nil
            if type(status) ~= "string" then
                ci_text, ci_run = "none", nil
                fill()
                return ci:set({ drawing = false, update_freq = 300 })
            end
            -- `gh run view --web` refuses without an id when not interactive, so
            -- the row is only clickable once we have one.
            ci_run = tonumber(run.databaseId)
            local conclusion = type(run.conclusion) == "string" and run.conclusion or nil
            local running = status ~= "completed"
            ci_text = running and status or (conclusion or status)
            fill()
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
        local key = string.format("%s\n%s", root or "", branch or "")
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

    -- No click_script: an item that has one never forwards mouse events to the
    -- lua bridge, so mouse.exited.global would never fire and the popup would
    -- stay open until clicked again.
    repo:subscribe("mouse.clicked", function()
        repo:set({ popup = { drawing = "toggle" } })
        refresh()
    end)
    repo:subscribe("mouse.exited.global", function()
        repo:set({ popup = { drawing = false } })
    end)

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

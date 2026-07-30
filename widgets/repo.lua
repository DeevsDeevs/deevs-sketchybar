-- repo widget: the git repo you are working in — name, branch, dirty count, optional
-- CI dot. Nothing outside the shell can tell which terminal pane has focus, so a zsh
-- chpwd/precmd hook pushes the cwd (--trigger repo_cwd RPATH="$PWD"); `path` pins one repo.
return function(ctx)
    local p = ctx.palette
    -- `repo = true` is valid config (see widgets/init.lua): check before indexing.
    local cfg = type(ctx.config.repo) == "table" and ctx.config.repo or {}

    local BRANCH_GLYPH, COMMIT_GLYPH, DOT = "\u{e725}", "\u{e729}", "\u{f0765}"
    -- 118px ≈ 17 chars at 11px, 21 at 9px (JetBrainsMono); the chip must not push the bar.
    local NAME_MAX, BRANCH_MAX = 20, 17

    -- A branch's meaning is in its tail, not the type prefix.
    local TYPE_PREFIX = { "feature/", "refactor/", "release/", "hotfix/",
                          "bugfix/", "chore/", "feat/", "docs/", "test/", "fix/" }
    local CI_FLOOR = 10 -- burst guard on gh; the real cadence is ci's update_freq

    -- A skipped or cancelled run says nothing about the code: unknown, not red.
    local VERDICT = {
        success   = p.good,
        skipped   = ctx.with_alpha(p.fg, 0.35),
        neutral   = ctx.with_alpha(p.fg, 0.35),
        cancelled = ctx.with_alpha(p.fg, 0.35),
    }

    -- Only `~` and `~/…`: `~otheruser` is a shell feature, and a $HOME gsub would need % escaping.
    local function expand(path)
        local home = os.getenv("HOME")
        if not home then return path end
        if path == "~" then return home end
        return path:sub(1, 2) == "~/" and (home .. path:sub(2)) or path
    end

    local pinned = cfg.path and expand(cfg.path) or nil

    -- io.popen sees the same environment as sbar.exec, so a hit here is runnable in callbacks.
    local function have(tool)
        local f = io.popen("command -v " .. tool .. " 2>/dev/null")
        local found = (f and f:read("*a") or "") ~= ""
        if f then f:close() end
        return found
    end

    -- Clip by codepoint: a byte sub can cut a multibyte character in half.
    local function clip(value, limit)
        local str = tostring(value or "")
        local cut = utf8.offset(str, limit + 1)
        return cut and string.format("%s…", str:sub(1, cut - 1)) or str
    end

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

    -- SbarLua's exec stdout is not NUL-terminated and can carry a garbage tail: first line only.
    local function first_line(out)
        local str = tostring(out or ""):match("[^\r\n]+") or ""
        return (str:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- Right-position items lay out right-to-left in creation order: created first,
    -- so the dot lands right of the text.
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

    -- Two-line stack, as in media.lua: two items share one box only when both labels
    -- carry the SAME fixed width; width = 0 does not collapse an item.
    local TEXT_W = 118

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

    -- Popup rows carry the untruncated detail; popup children are not bar items,
    -- so they join no group or cluster.
    local ROWS = { "repo", "branch", "upstream", "changes", "last", "ci" }
    local rows, actions = {}, {}
    for _, key in ipairs(ROWS) do
        rows[key] = sbar.add("item", string.format("widgets.repo.row.%s", key), {
            position = string.format("popup.%s", repo.name),
            icon = { string = key, width = 76, align = "left",
                     color = ctx.with_alpha(p.fg, 0.45) },
            label = { string = "—", width = 300, align = "left" },
        })
        rows[key]:subscribe("mouse.clicked", function()
            repo:set({ popup = { drawing = false } })
            local action = actions[key]
            if action then sbar.exec(action()) end
        end)
    end

    -- Only $EDITOR's first word: a blocking flag ("zeditor --wait") would hang the
    -- exec child until SbarLua's alarm(60) kills it. Falls back to `open`.
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
        -- Away from the repo, dim rather than hide: hiding reflows the bar.
        top_line:set({ label = {
            string = clip(name, NAME_MAX),
            color = ctx.with_alpha(p.fg, here and 0.5 or 0.25),
        } })
        repo:set({
            -- Detached HEAD (mid-rebase, checked-out tag): short SHA under a commit glyph.
            icon = { string = branch and BRANCH_GLYPH or COMMIT_GLYPH,
                     color = ctx.with_alpha(p.fg, here and 0.7 or 0.3) },
            label = { string = string.format("%s%s", lower, suffix),
                      color = ctx.with_alpha(p.fg, here and 0.9 or 0.45) },
        })
    end

    -- Only the commit subject is clipped: it has no natural bound.
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

        -- gh browse / gh run view resolve the remote themselves.
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

    -- SbarLua recycles exec callback refs, so a reply can be delivered to a different
    -- exec's callback: the helper echoes the directory asked, mismatches are dropped.
    poll = function(dir)
        if not dir then return end
        sbar.exec(string.format("%s %s",
            ctx.shell_quote(ctx.helper("repo_state.sh")),
            ctx.shell_quote(dir)), function(out)
            local verdict, asked, rest = first_line(out):match("^(%a+)\t([^\t]*)\t?(.*)$")
            if asked ~= dir then return end -- not our reply

            if verdict == "no" then
                -- Not a repo: hold the last one, dimmed.
                here = false
                return paint()
            end

            local top, head, oid, count, st, un, q, ah, bh, up, subj = rest:match(
                "^([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]*)\t?(.*)$")
            if not top then
                -- One bad read is usually index.lock contention; only a repeated miss retires the chip.
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

    -- Routine re-polls the last directory: edits and rebases in other tabs never fire the shell hook.
    refresh = function() poll(pinned or seen_cwd or root) end

    -- Unfiltered, gh answers for whichever branch ran last; detached HEAD has no branch to ask about.
    ci_fetch = function()
        if not (ci and root and branch) then return end
        if os.time() - ci_at < CI_FLOOR then return end
        ci_at = os.time()
        -- gh has no -C, so cd; </dev/null stops gh prompting when it thinks it has a terminal.
        sbar.exec(string.format(
            "cd %s && gh run list --branch %s --limit 1 --json status,conclusion,databaseId </dev/null 2>/dev/null",
            ctx.shell_quote(root), ctx.shell_quote(branch)), function(out)
            -- JSON array/object stdout arrives parsed into a lua table. gh prints
            -- nothing at all with no remote, no run on this branch, or no credentials.
            local run = type(out) == "table" and out[1] or nil
            local status = type(run) == "table" and run.status or nil
            if type(status) ~= "string" then
                ci_text, ci_run = "none", nil
                fill()
                return ci:set({ drawing = false, update_freq = 300 })
            end
            -- gh run view --web refuses without an id when non-interactive.
            ci_run = tonumber(run.databaseId)
            local conclusion = type(run.conclusion) == "string" and run.conclusion or nil
            local running = status ~= "completed"
            ci_text = running and status or (conclusion or status)
            fill()
            ci:set({
                drawing = true,
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
        -- A verdict belongs to one repo+branch, so clear the dot on switch; poll
        -- faster until the new answer lands in case the burst guard swallowed this fetch.
        ci:set({ drawing = false, update_freq = 60 })
        ci_fetch()
    end

    -- repo_cwd is not a reserved built-in event name; triggers on reserved names
    -- (e.g. media_change) are silently swallowed.
    sbar.add("event", "repo_cwd")

    repo:subscribe({ "routine", "forced", "system_woke" }, refresh)
    -- Every tick of the dot is a network call, so it keeps its own slower clock.
    if ci then ci:subscribe({ "routine", "forced", "system_woke" }, ci_fetch) end

    -- No click_script: an item with one never forwards mouse events, so
    -- mouse.exited.global would never fire and the popup would stay open.
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
            -- Same directory again: precmd fires on every bare Enter, hence the floor.
            if os.time() - seen_at < 1 then return end
            seen_at = os.time()
            poll(cwd)
        end)
    end

    -- Routine is up to update_freq away; a pinned repo would sit on "—" after reload.
    if pinned then poll(pinned) end
end

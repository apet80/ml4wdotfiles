-- Git diff / merge integration for `git difftool` and `git mergetool`.
--
-- Git drives Neovim directly once its config points at the built-in
-- `nvimdiff` backend (see README.md -> "Git diff & merge"):
--
--   * difftool  -> `nvim -R -f -d LOCAL REMOTE`              (2-way, read-only)
--   * mergetool -> `nvim -f LOCAL BASE REMOTE MERGED`, laid out as
--                  (LOCAL,BASE,REMOTE)/MERGED with all four in diff mode
--
-- Git names its scratch files `<name>_LOCAL_<pid>.<ext>` (likewise BASE /
-- REMOTE / BACKUP) and keeps the real path as MERGED, so the `:diffget LOCAL`
-- family below resolves each side by a buffer-name match.

local M = {}

-- True when this Neovim was started by `git difftool` / `git mergetool`.
-- `-d` (difftool) sets 'diff' before user config runs; mergetool does not pass
-- `-d`, so also sniff argv for git's scratch-file naming.
local function detect_session()
    if vim.o.diff then
        return true
    end
    for _, arg in ipairs(vim.fn.argv()) do
        if arg:match("_LOCAL_%d+%.%w+$")
            or arg:match("_REMOTE_%d+%.%w+$")
            or arg:match("_BASE_%d+%.%w+$")
            or arg:match("_BACKUP_%d+%.%w+$")
        then
            return true
        end
    end
    return false
end

M.session = detect_session()

-- Diff algorithm & appearance. Neovim 0.12 already defaults to
--   internal,filler,closeoff,indent-heuristic,inline:char,linematch:40
-- histogram + a wider linematch window give noticeably cleaner hunks on
-- real-world merges.
vim.opt.diffopt = {
    "internal",
    "filler",
    "closeoff",
    "indent-heuristic",
    "algorithm:histogram",
    "inline:char",
    "linematch:60",
}

-- Diagonal fill for removed lines instead of a run of '-'.
vim.opt.fillchars:append({ diff = "╱" })

local group = vim.api.nvim_create_augroup("git-diff-merge", { clear = true })

-- Buffer-local mappings for a buffer shown in a diff window. `merge` adds the
-- 3-way pickers, which only make sense when BASE/LOCAL/REMOTE are all present.
local function attach_diff_maps(buf, merge)
    if vim.b[buf].diff_maps_done then
        return
    end
    vim.b[buf].diff_maps_done = true

    local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
    end

    -- 2-way (difftool): grab / send the hunk under the cursor. Built-in
    -- `do` / `dp` do the same; these just carry a description and a refresh.
    map("<leader>dg", "<cmd>diffget<CR>", "Diff: get hunk from the other side")
    map("<leader>dp", "<cmd>diffput<CR>", "Diff: put hunk to the other side")
    map("<leader>du", "<cmd>diffupdate<CR>", "Diff: recompute")

    if merge then
        -- 3-way (mergetool): pull the conflicting hunk from one side into MERGED.
        map("<leader>1", "<cmd>diffget LOCAL<CR>", "Merge: take hunk from LOCAL (ours)")
        map("<leader>2", "<cmd>diffget BASE<CR>", "Merge: take hunk from BASE (ancestor)")
        map("<leader>3", "<cmd>diffget REMOTE<CR>", "Merge: take hunk from REMOTE (theirs)")
    end
end

local function scan_windows()
    local diff_wins = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].diff then
            diff_wins[#diff_wins + 1] = win
        end
    end
    local merge = #diff_wins >= 3
    for _, win in ipairs(diff_wins) do
        attach_diff_maps(vim.api.nvim_win_get_buf(win), merge)
    end
end

-- `nvim -d` / mergetool establish their diff windows during startup, before
-- OptionSet fires -- pick them up once the UI is ready.
vim.api.nvim_create_autocmd("VimEnter", { group = group, callback = scan_windows })

-- Later `:diffthis` / `:windo diffthis` in an already-running session.
vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "diff",
    callback = function()
        if vim.v.option_new == true then
            vim.schedule(scan_windows)
        end
    end,
})

if M.session then
    -- The scratch buffers are throwaway: no diagnostics gutter stealing width
    -- in the 4-pane layout, and no persisted undo history for temp files.
    vim.opt.signcolumn = "no"
    vim.opt.undofile = false
end

return M

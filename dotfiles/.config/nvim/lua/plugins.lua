-- Plugin management via vim.pack (Neovim 0.12+)
-- Full GitHub URL required — vim.pack does NOT expand short "user/repo" paths.

vim.pack.add({
    { src = "https://github.com/folke/tokyonight.nvim" },
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})

-- Configure and apply the colorscheme.
-- vim.pack.add() is synchronous on first install; plugin is available immediately after.
require("tokyonight").setup({
    style = "night",        -- "storm" | "night" | "moon" | "day"
    transparent = false,
    terminal_colors = true,
    styles = {
        comments = { italic = true },
        keywords = { italic = true },
    },
})

vim.cmd.colorscheme("tokyonight")

-- Treesitter: parsers for the languages this config is used with day to day.
-- Requires a C compiler (cc/gcc) on PATH to build parsers on first install.
local ts_langs = { "lua", "python", "bash", "vim", "vimdoc", "query", "markdown", "markdown_inline" }
require("nvim-treesitter").install(ts_langs)

vim.api.nvim_create_autocmd("FileType", {
    pattern = ts_langs,
    callback = function()
        vim.treesitter.start()
        vim.bo.indentexpr = "v:lua.vim.treesitter.indentexpr()"
    end,
})

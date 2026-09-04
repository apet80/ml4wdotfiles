-- LSP configuration (native Neovim 0.11+ API — nvim-lspconfig only supplies
-- the default server configs; no :setup() call needed).
--
-- Requires the actual servers/formatters to be installed and on PATH:
--   lua_ls   -> pacman -S lua-language-server
--   pyright  -> npm i -g pyright   (or basedpyright)
--   ruff     -> pacman -S ruff     (linter + formatter, also speaks LSP)
--   bashls   -> npm i -g bash-language-server
--   shellcheck, stylua, shfmt are picked up by the servers above for
--   diagnostics/formatting where applicable.

-- Don't spin up language servers when Neovim is acting as git's
-- difftool/mergetool -- the buffers are throwaway scratch files.
if require("diff").session then
    return
end

vim.lsp.config("lua_ls", {
    settings = {
        Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
        },
    },
})

vim.lsp.enable({ "lua_ls", "pyright", "ruff", "bashls" })

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        local bufnr = args.buf

        if client and client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
        end

        local opts = { buffer = bufnr, silent = true }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format({ async = true })
        end, opts)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    end,
})

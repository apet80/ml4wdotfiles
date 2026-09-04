# Neovim config

Minimal Neovim 0.12+ setup. Vim-level options come from the shared vimrc that
`init.vim` sources (`~/projects/ml4wdotfiles/dotfiles/.config/vim/.vimrc`);
everything Neovim-specific lives here.

| File | Purpose |
| --- | --- |
| `init.vim` | Entry point: loads the modules below in order. |
| `lua/options.lua` | Neovim-only options not covered by the shared vimrc. |
| `lua/plugins.lua` | `vim.pack` plugins (tokyonight, nvim-lspconfig, nvim-treesitter) + Treesitter setup. |
| `lua/diff.lua` | `git difftool` / `git mergetool` integration (see below). |
| `lua/keymaps.lua` | Plugin-independent keymaps. |
| `lua/lsp.lua` | Native LSP (`lua_ls`, `pyright`, `ruff`, `bashls`). Skipped in a diff/merge session. |
| `ftplugin/lua.lua` | 2-space indent for Lua. |

## Git diff & merge

Git drives Neovim through its built-in `nvimdiff` backend. The required global
git config (already applied on this machine):

```sh
git config --global diff.tool  nvimdiff
git config --global merge.tool nvimdiff
git config --global mergetool.nvimdiff.layout "(LOCAL,BASE,REMOTE)/MERGED"
git config --global merge.conflictStyle  zdiff3   # 3-way conflict markers
git config --global mergetool.prompt     false    # don't ask before each file
git config --global mergetool.keepBackup false    # no *.orig after a clean merge
git config --global mergetool.writeToTemp true    # keep scratch files out of the tree
git config --global difftool.prompt      false
```

- `git difftool [<rev>] [-- <path>]` → `nvim -R -d LOCAL REMOTE` (2-way, read-only).
- `git mergetool` → four windows in diff mode: `LOCAL` / `BASE` / `REMOTE` on
  top, the working file (`MERGED`) below. Edit `MERGED`, then `:wqa`
  (or `:cq` to abort the merge).

### Keymaps (active only in a diff window)

| Key | Action |
| --- | --- |
| `]c` / `[c` | next / previous change (built-in) |
| `<leader>dg` / `do` | get the hunk under the cursor from the other side |
| `<leader>dp` / `dp` | put the hunk under the cursor to the other side |
| `<leader>du` | recompute the diff |
| `<leader>1` | *(merge)* take the hunk from `LOCAL` (ours) |
| `<leader>2` | *(merge)* take the hunk from `BASE` (common ancestor) |
| `<leader>3` | *(merge)* take the hunk from `REMOTE` (theirs) |

`<leader>` is `<Space>`. In a 3-way merge `do` / `dp` are ambiguous — use the
numbered `<leader>1/2/3` pickers from the `MERGED` window instead.

`lua/diff.lua` also widens `linematch` and switches the diff algorithm to
`histogram` for cleaner hunks, draws removed lines with a `╱` fill, and — when
Neovim was launched as a diff/merge tool — disables the sign column, persisted
undo, and language servers for the throwaway scratch buffers.

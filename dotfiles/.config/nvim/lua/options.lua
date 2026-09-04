-- Neovim-specific options not covered by the shared vimrc
-- (see ~/projects/ml4wdotfiles/dotfiles/.config/vim/.vimrc for the base config)

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.termguicolors = true      -- true color, required for tokyonight to render correctly
vim.opt.clipboard = "unnamedplus" -- share the system clipboard (wl-copy/xclip)
vim.opt.undofile = true           -- persist undo history across sessions
vim.opt.splitright = true         -- vertical splits open to the right
vim.opt.splitbelow = true         -- horizontal splits open below
vim.opt.signcolumn = "yes"        -- reserve space so diagnostics don't shift text
vim.opt.completeopt = "menuone,noselect,popup"

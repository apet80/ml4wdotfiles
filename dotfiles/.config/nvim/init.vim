lua require("options")

set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/projects/ml4wdotfiles/dotfiles/.config/vim/.vimrc

" Load vim.pack plugins and colorscheme (Neovim 0.12+)
lua require("plugins")
lua require("diff")
lua require("keymaps")
lua require("lsp")

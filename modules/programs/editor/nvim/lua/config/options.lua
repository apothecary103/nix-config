vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.o

o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.showmode = false
o.showtabline = 0
o.winborder = "solid"
o.pumheight = 12
o.fillchars = "eob: ,fold: ,foldsep: ,foldopen:▾,foldclose:▸,diff:╱"

o.expandtab = true
o.tabstop, o.shiftwidth, o.softtabstop = 4, 4, 4
o.shiftround = true
o.smartindent = true

o.undofile = false
o.swapfile = false
o.backup = false
o.writebackup = false

o.ignorecase = true
o.smartcase = true
o.inccommand = "nosplit"
o.scrolloff = 5
o.sidescrolloff = 8
o.jumpoptions = "stack,view"

o.updatetime = 250
o.timeoutlen = 300

o.splitright = true
o.splitbelow = true
o.splitkeep = "screen"

o.wrap = true
o.linebreak = true
o.breakindent = true
o.showbreak = "↪ "

o.foldlevel = 99
o.foldtext = ""

o.completeopt = "menu,menuone,noselect,fuzzy,popup"
o.confirm = true
o.mouse = "a"
o.virtualedit = "block"
o.shortmess = o.shortmess .. "sIc"
o.guicursor = "n-c-sm:block,i-ci-ve:ver25,v:hor20,r-cr:hor20,o:hor50"

for _, p in ipairs({ "perl", "ruby", "node", "python3" }) do
	vim.g["loaded_" .. p .. "_provider"] = 0
end

vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_remote_plugins = 1

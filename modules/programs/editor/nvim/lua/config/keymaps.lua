local function map(mode, lhs, rhs, desc, opts)
	vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { silent = true, desc = desc }, opts or {}))
end

map("n", "<Esc>", function()
	vim.cmd.nohlsearch()
	Snacks.notifier.hide()
end, "Clear highlights")

map({ "n", "i", "x" }, "<C-s>", "<Esc><cmd>write<cr>", "Save")
map("n", "<leader>qq", "<cmd>qa<cr>", "Quit all")

for _, k in ipairs({ "h", "j", "k", "l" }) do
	map("n", "<C-" .. k .. ">", "<C-w>" .. k, "Window " .. k)
end

-- Tabs
map("n", "<leader>tn", "<cmd>tabnew<cr>", "New tab")
map("n", "<leader>tc", "<cmd>tabclose<cr>", "Close tab")
-- Not <Tab>/<S-Tab>: <Tab> is <C-i>, the jumplist-forward motion.
map("n", "]t", "<cmd>tabnext<cr>", "Next tab")
map("n", "[t", "<cmd>tabprevious<cr>", "Previous tab")

-- Buffers
map("n", "<S-l>", "<cmd>bnext<cr>", "Next buffer")
map("n", "<S-h>", "<cmd>bprevious<cr>", "Previous buffer")
map("n", "<leader>bd", function() Snacks.bufdelete() end, "Delete buffer")
map("n", "<leader>bo", function() Snacks.bufdelete.other() end, "Delete other buffers")

map("n", "<C-d>", "<C-d>zz", "Half page down")
map("n", "<C-u>", "<C-u>zz", "Half page up")
map("n", "n", "nzzzv", "Next match")
map("n", "N", "Nzzzv", "Previous match")

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", "Down", { expr = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", "Up", { expr = true })

map("x", "<", "<gv", "Indent left")
map("x", ">", ">gv", "Indent right")
map("x", "p", [["_dP]], "Paste without yanking")
map({ "n", "x" }, "<leader>y", [["+y]], "Yank to clipboard")
map({ "n", "x" }, "<leader>p", [["+p]], "Paste from clipboard")

-- Toggles
map("n", "<leader>uw", function() vim.wo.wrap = not vim.wo.wrap end, "Toggle wrap")
map("n", "<leader>ud", function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end, "Toggle diagnostics")
map("n", "<leader>uh", function()
	vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, "Toggle inlay hints")
map("n", "<leader>uv", function()
	local on = not (vim.diagnostic.config() or {}).virtual_lines
	vim.diagnostic.config({ virtual_lines = on and { current_line = true } or false, virtual_text = not on })
end, "Toggle virtual lines")

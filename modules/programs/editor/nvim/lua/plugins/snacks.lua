local border = require("config.ui").border

-- NvChad's telescope look, minus the lines: a one-line prompt box, a separate
-- results box below it, preview on the right. The boxes are still titled and
-- still padded -- the `solid` border just draws no visible edge.
local function boxes(width, height, preview)
	local left = {
		box = "vertical",
		{ win = "input", height = 1, border = border, title = " {title} {live} {flags} ", title_pos = "center" },
		{ win = "list", border = border },
	}
	if not preview then
		left.width, left.height = width, height
		return { layout = left }
	end
	return {
		layout = {
			box = "horizontal",
			width = width,
			height = height,
			left,
			{ win = "preview", border = border, title = " {preview} ", title_pos = "center", width = 0.55 },
		},
	}
end

local keys = {
	{ "<leader><space>", function() Snacks.picker.smart() end, "Smart find" },
	{ "<leader>ff", function() Snacks.picker.files() end, "Files" },
	{ "<leader>fg", function() Snacks.picker.grep() end, "Grep" },
	{ "<leader>fw", function() Snacks.picker.grep_word() end, "Grep word", { "n", "x" } },
	{ "<leader>fb", function() Snacks.picker.buffers() end, "Buffers" },
	{ "<leader>fo", function() Snacks.picker.recent() end, "Recent" },
	{ "<leader>fr", function() Snacks.picker.resume() end, "Resume" },
	{ "<leader>fh", function() Snacks.picker.help() end, "Help" },
	{ "<leader>fk", function() Snacks.picker.keymaps() end, "Keymaps" },
	{ "<leader>fd", function() Snacks.picker.diagnostics() end, "Diagnostics" },
	{ "<leader>f/", function() Snacks.picker.lines() end, "Buffer lines" },
	{ "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, "Config" },
	{ "<leader>fC", function() Snacks.picker.colorschemes() end, "Colourschemes" },
	{ "<C-\\>", function() Snacks.terminal.toggle() end, "Terminal", { "n", "t" } },
}

return {
	{
		"snacks.nvim",
		priority = 1000,
		after = function()
			require("snacks").setup({
				bigfile = { enabled = true },
				quickfile = { enabled = true },
				input = { enabled = true },
				notifier = { enabled = true, style = "compact" },
				-- indent = { enabled = true, indent = { char = "│" }, animate = { enabled = false } },
				scope = { enabled = true },
				bufdelete = { enabled = true },
				rename = { enabled = true },
				terminal = { win = { border = border } },

				picker = {
					prompt = "   ", -- nf-fa-search, NvChad's telescope prompt_prefix
					ui_select = true,
					layout = boxes(0.87, 0.8, true),
					layouts = { compact = boxes(0.6, 0.55, false) },
					matcher = { frecency = true, cwd_bonus = true },
					formatters = { file = { truncate = 80 } },
					sources = {
						files = { hidden = true },
						grep = { hidden = true },
						buffers = { layout = "compact", current = false },
						keymaps = { layout = "compact" },
					},
					win = {
						-- Without lines to hold them apart, the boxes need a little
						-- more air: a spare gutter column on each side of the results
						-- and the preview.
						list = { wo = { statuscolumn = " " } },
						preview = { wo = { signcolumn = "yes", numberwidth = 4 } },
						input = {
							keys = {
								["<Esc>"] = { "close", mode = { "n", "i" } },
								["<C-j>"] = { "list_down", mode = { "i", "n" } },
								["<C-k>"] = { "list_up", mode = { "i", "n" } },
								["<C-q>"] = { "qflist", mode = { "i", "n" } },
								["<C-v>"] = { "edit_vsplit", mode = { "i", "n" } },
							},
						},
					},
				},
			})

			for _, k in ipairs(keys) do
				vim.keymap.set(k[4] or "n", k[1], k[2], { silent = true, desc = k[3] })
			end
		end,
	},
}

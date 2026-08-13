local border = require("config.ui").border

return {
	{
		"flash.nvim",
		keys = {
			{ "s", function() require("flash").jump() end, mode = { "n", "x", "o" }, desc = "Flash" },
			{ "S", function() require("flash").treesitter() end, mode = { "n", "x", "o" }, desc = "Flash treesitter" },
			{ "r", function() require("flash").remote() end, mode = "o", desc = "Remote flash" },
		},
		after = function()
			require("flash").setup({ modes = { char = { jump_labels = true } } })
		end,
	},

	{
		"which-key.nvim",
		event = "DeferredUIEnter",
		after = function()
			require("which-key").setup({
				preset = "helix",
				win = { border = border },
				icons = { rules = false },
				spec = {
					{ "<leader>b", group = "buffer" },
					{ "<leader>c", group = "code" },
					{ "<leader>f", group = "find" },
					{ "<leader>g", group = "git" },
					{ "<leader>t", group = "tab" },
					{ "<leader>u", group = "toggle" },
					{ "gs", group = "surround" },
				},
			})
		end,
	},

	-- Directory as an editable buffer, not a tree. Not deferred, because opening
	-- nvim on a directory has to land in oil rather than in netrw.
	{
		"oil.nvim",
		after = function()
			require("oil").setup({
				delete_to_trash = true,
				skip_confirm_for_simple_edits = true,
				watch_for_changes = true,
				view_options = { show_hidden = true, natural_order = true },
				win_options = { signcolumn = "no", number = false, relativenumber = false },
				float = { border = border },
				keymaps = { ["<C-h>"] = false, ["<C-l>"] = false, ["<C-c>"] = "actions.close" },
			})
			vim.keymap.set("n", "-", "<cmd>Oil<cr>", { silent = true, desc = "Parent directory" })
		end,
	},

	{
		"gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		after = function()
			require("gitsigns").setup({
				signs = { add = { text = "▎" }, change = { text = "▎" }, untracked = { text = "▎" } },
				preview_config = { border = border },
				on_attach = function(buf)
					local gs = require("gitsigns")
					local function map(mode, lhs, rhs, desc)
						vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
					end
					map("n", "]h", function() gs.nav_hunk("next") end, "Next hunk")
					map("n", "[h", function() gs.nav_hunk("prev") end, "Previous hunk")
					map({ "n", "x" }, "<leader>gs", gs.stage_hunk, "Stage hunk")
					map({ "n", "x" }, "<leader>gr", gs.reset_hunk, "Reset hunk")
					map("n", "<leader>gp", gs.preview_hunk_inline, "Preview hunk")
					map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
					map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
				end,
			})
		end,
	},
}

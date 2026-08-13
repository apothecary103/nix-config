-- Replaces nvim-web-devicons for every plugin that still requires it.
-- No `file`/`filetype` overrides: mini.icons already knows every extension
-- here, and an override whose glyph goes missing silently blanks the icon.
package.preload["nvim-web-devicons"] = function()
	require("mini.icons").mock_nvim_web_devicons()
	return package.loaded["nvim-web-devicons"]
end

return {
	{ "mini.icons", after = function() require("mini.icons").setup({}) end },

	-- Helix-style modeline: mode pill, filename, then LSP, diagnostics, position.
	{
		"mini.statusline",
		event = "DeferredUIEnter",
		after = function()
			require("mini.statusline").setup({
				use_icons = true,
				content = {
					active = function()
						local st = require("mini.statusline")
						local mode, mode_hl = st.section_mode({ trunc_width = 120 })
						return st.combine_groups({
							{ hl = mode_hl, strings = { mode:upper() } },
							{ hl = "MiniStatuslineFilename", strings = { st.section_filename({ trunc_width = 140 }) } },
							"%=",
							{ hl = "MiniStatuslineDevinfo", strings = { require("config.ui").lsp_indicator() } },
							{ hl = "MiniStatuslineDevinfo", strings = { st.section_diagnostics({ trunc_width = 75 }) } },
							{ hl = "MiniStatuslineFilename", strings = { "%l:%v" } },
						})
					end,
				},
			})
		end,
	},

	-- Its setup() hardcodes showtabline=2 with no opt-out, so config/autocmds.lua
	-- takes the setting back afterwards and toggles it per buffer count.
	{
		"mini.tabline",
		event = "DeferredUIEnter",
		after = function() require("mini.tabline").setup({ show_icons = true }) end,
	},

	-- gs prefix, because plain s/S belong to flash.
	{
		"mini.surround",
		keys = { { "gs", mode = { "n", "x" }, desc = "Surround" } },
		after = function()
			require("mini.surround").setup({
				mappings = {
					add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF",
					highlight = "gsh", replace = "gsr", update_n_lines = "gsn",
				},
				silent = true,
			})
		end,
	},

	-- af/if and ac/ic come from nvim-treesitter-textobjects; this adds the rest.
	{
		"mini.ai",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("mini.ai").setup({
				n_lines = 500,
				custom_textobjects = {
					o = require("mini.ai").gen_spec.treesitter({
						a = { "@block.outer", "@conditional.outer", "@loop.outer" },
						i = { "@block.inner", "@conditional.inner", "@loop.inner" },
					}),
					i = require("snacks.scope").textobject,
				},
			})
		end,
	},

	{
		"mini.pairs",
		event = "InsertEnter",
		after = function()
			require("mini.pairs").setup({ modes = { insert = true, command = true }, skip_ts = { "string" } })
		end,
	},

	{
		"mini.move",
		keys = {
			{ "<A-h>", mode = { "n", "x" } }, { "<A-l>", mode = { "n", "x" } },
			{ "<A-j>", mode = { "n", "x" } }, { "<A-k>", mode = { "n", "x" } },
		},
		after = function() require("mini.move").setup({}) end,
	},
}

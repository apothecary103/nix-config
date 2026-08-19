return {
	{
		"luna.nvim",
		priority = 1000,
		after = function()
			require("luna").setup({ styles = { comments = { italic = true } } })
			vim.cmd.colorscheme("luna")
		end,
	},

	-- Loaded but not applied: setup() only records the options, so the picker can
	-- offer these and they come up configured when chosen.
	{
		"evergarden",
		after = function()
			require("evergarden").setup({ theme = { variant = "fall", accent = "green" } })
		end,
	},

	{
		"catppuccin-nvim",
		after = function()
			require("catppuccin").setup({ background = { light = "latte", dark = "macchiato" } })
		end,
	},

	{ "bg.nvim" },
}

-- The `main` branch is only a parser installer, and Nix has already done that
-- job: `ensure_installed`, `highlight` and `indent` opts do nothing, and the
-- parsers arrive on the runtimepath rather than in nvim-treesitter's own
-- install dir. Features are Neovim's, enabled per buffer below.
return {
	{
		"nvim-treesitter",
		after = function()
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(ev)
					local lang = vim.treesitter.language.get_lang(ev.match)
					-- get_installed() reads that empty install dir, so it would answer
					-- "nothing" for every language. Whether start() takes is the only
					-- test that means anything here.
					if not lang or not pcall(vim.treesitter.start, ev.buf, lang) then return end

					vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
					vim.wo[0][0].foldmethod = "expr"
					if not vim.tbl_contains({ "lua", "python", "vim", "markdown" }, ev.match) then
						vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},

	{
		"nvim-treesitter-textobjects",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("nvim-treesitter-textobjects").setup({ select = { lookahead = true } })
			local select = require("nvim-treesitter-textobjects.select")
			local move = require("nvim-treesitter-textobjects.move")

			for lhs, query in pairs({
				af = "@function.outer", ["if"] = "@function.inner",
				ac = "@class.outer", ic = "@class.inner",
				aa = "@parameter.outer", ia = "@parameter.inner",
				["a="] = "@assignment.outer", ["i="] = "@assignment.inner",
			}) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					select.select_textobject(query, "textobjects")
				end, { desc = "Select " .. query })
			end

			for lhs, spec in pairs({
				["]f"] = { move.goto_next_start, "@function.outer" },
				["[f"] = { move.goto_previous_start, "@function.outer" },
				["]c"] = { move.goto_next_start, "@class.outer" },
				["[c"] = { move.goto_previous_start, "@class.outer" },
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					spec[1](spec[2], "textobjects")
				end, { desc = "Move " .. spec[2] })
			end
		end,
	},
}

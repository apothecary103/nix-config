-- prettier owns everything web: it reads the project's own config and plugins
-- (prettier-plugin-svelte, prettier-plugin-tailwindcss), which the language
-- servers do not. prettierd is the same formatter behind a daemon, so the
-- one-shot binary is only the fallback when the daemon is missing.
local prettier = { "prettierd", "prettier", stop_after_first = true }

-- Both have to be set before conform loads: the toggle is read by the
-- format_on_save callback below, and formatexpr is what makes `gq` pull conform
-- in in the first place.
vim.g.autoformat = false
vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

return {
	{
		"conform.nvim",
		event = "BufWritePre",
		cmd = "ConformInfo",
		keys = {
			{
				"<leader>cf",
				function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
				mode = { "n", "x" },
				desc = "Format",
			},
			{
				"<leader>uf",
				function()
					vim.g.autoformat = not vim.g.autoformat
					vim.notify("Format on save " .. (vim.g.autoformat and "on" or "off"))
				end,
				desc = "Toggle format on save",
			},
		},
		after = function()
			require("conform").setup({
				default_format_opts = { lsp_format = "fallback" },
				formatters = {
					-- nu-lint's own rewrites are rule fixes, not layout, so they run
					-- before nufmt reflows the result.
					nu_lint = {
						meta = {
							url = "https://codeberg.org/wvhulle/nu-lint",
							description = "Auto-fix nu-lint violations.",
						},
						command = "nu-lint",
						args = { "--fix", "$FILENAME" },
						stdin = false,
					},
				},
				formatters_by_ft = {
					lua = { "stylua" },
					nix = { "nixfmt" },
					fish = { "fish_indent" },
					sh = { "shfmt" },
					bash = { "shfmt" },
					nu = { "nu_lint", "nufmt" },
					toml = { "taplo" },
					javascript = prettier,
					javascriptreact = prettier,
					typescript = prettier,
					typescriptreact = prettier,
					svelte = prettier,
					html = prettier,
					css = prettier,
					scss = prettier,
					less = prettier,
					json = prettier,
					jsonc = prettier,
					yaml = prettier,
					graphql = prettier,
					markdown = prettier,
					-- ruff_fix applies the lint autofixes, ruff_organize_imports the
					-- import sort, ruff_format the layout — in that order.
					python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
					rust = { "rustfmt" },
					go = { "gofumpt", "goimports" },
				},
				format_on_save = function()
					return vim.g.autoformat and { timeout_ms = 2000, lsp_format = "fallback" } or nil
				end,
			})
		end,
	},
}

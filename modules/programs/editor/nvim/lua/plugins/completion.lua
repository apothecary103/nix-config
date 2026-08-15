local border = require("config.ui").border

return {
	-- Snippet data only, so it just has to be on the runtimepath before blink
	-- reads it.
	{ "friendly-snippets", dep_of = "blink.cmp" },

	{
		"blink.cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		-- lspconfig asks blink for its client capabilities, which means blink has
		-- to be loaded by then even if no insert has happened yet.
		dep_of = "nvim-lspconfig",
		after = function()
			require("blink.cmp").setup({
				keymap = {
					preset = "default",
					["<CR>"] = { "accept", "fallback" },
					["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
					["<Tab>"] = { "snippet_forward", "fallback" },
					["<S-Tab>"] = { "snippet_backward", "fallback" },
				},
				appearance = { nerd_font_variant = "mono" },
				completion = {
					accept = { auto_brackets = { enabled = true } },
					-- Topmost entry is always selected as you type; nothing is written into
					-- the buffer until <CR>, so the preselection never mangles the word.
					list = { selection = { preselect = true, auto_insert = false } },
					menu = {
						border = border,
						scrollbar = false,
						draw = {
							-- No treesitter colouring of labels: every item reads in the
							-- plain foreground, and only the kind column carries colour.
							padding = 2,
							gap = 2,
							-- NvChad order: "local      Keyword". The label side
							-- stretches so the icon/kind pair stays flush right.
							columns = {
								{ "label", "label_description", gap = 1 },
								{ "kind_icon", "kind", gap = 1 },
							},
						},
					},
					documentation = { auto_show = true, auto_show_delay_ms = 150, window = { border = border } },
				},
				signature = { enabled = true, window = { border = border } },
				sources = {
					-- lazydev yields nothing outside Lua, so it is safe to list globally
					-- for results; loading is what needs care, hence its `on_require`.
					default = { "lsp", "path", "snippets", "buffer", "lazydev" },
					providers = {
						lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
						buffer = { score_offset = -3 },
					},
				},
				fuzzy = { implementation = "prefer_rust_with_warning", frecency = { enabled = true } },
				-- The command line is not code, so it does not get the code menu.
				-- Only `draw.columns`, `list`, `ghost_text` and `auto_show` can be
				-- overridden per mode (border and padding are global), which is
				-- enough: dropping the kind column removes the icons and the
				-- "Keyword"/"Snippet" labels that made `:` read like an LSP popup.
				cmdline = {
					keymap = { preset = "cmdline" },
					-- Buffer words belong in `/` and `?`, not in `:`, where they
					-- bury the actual commands under whatever the file happens to
					-- contain. `@`, `>` and `=` are treated as `:`.
					sources = function()
						return vim.fn.getcmdtype():match("[/?]") and { "buffer" } or { "cmdline" }
					end,
					completion = {
						menu = {
							auto_show = true,
							draw = { columns = { { "label", "label_description", gap = 1 } } },
						},
						-- Wildmenu behaviour: nothing is selected until <Tab>, so
						-- <CR> always runs what was typed, and the selected item is
						-- written straight into the command line as you cycle.
						list = { selection = { preselect = false, auto_insert = true } },
						ghost_text = { enabled = false },
					},
				},
			})
		end,
	},
}

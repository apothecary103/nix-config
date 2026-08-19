-- Servers come from Nix/PATH; a missing binary just never attaches.
-- Customisation goes through vim.lsp.config() calls, never lsp/*.lua files:
-- plugin dirs come after the config dir in rtp, so nvim-lspconfig's own
-- lsp/<name>.lua would win over ours. Function calls are applied last.

-- tsserver takes the same inlay hint block under both `typescript` and
-- `javascript`; svelte's own defaults already cover the .svelte side.
local inlay_hints_ts = {
	includeInlayParameterNameHints = "literals",
	includeInlayParameterNameHintsWhenArgumentMatchesName = false,
	includeInlayFunctionParameterTypeHints = true,
	includeInlayVariableTypeHints = true,
	includeInlayVariableTypeHintsWhenTypeMatchesName = false,
	includeInlayPropertyDeclarationTypeHints = true,
	includeInlayFunctionLikeReturnTypeHints = true,
	includeInlayEnumMemberValueHints = true,
}

local servers = {
	lua_ls = {
		settings = {
			Lua = {
				workspace = { checkThirdParty = false },
				hint = { enable = true, setType = true },
				format = { enable = false },
				diagnostics = { unusedLocalExclude = { "_*" } },
			},
		},
	},
	nixd = {
		settings = {
			nixd = {
				nixpkgs = { expr = "import <nixpkgs> { }" },
				formatting = { command = { "nixfmt" } },
			},
		},
	},
	-- Python: ruff lints, fixes and formats; ty does types, hover and
	-- completion. Both attach to the same buffer, so ruff's overlapping
	-- capabilities are dropped below to keep answers coming from the checker.
	ruff = {
		init_options = {
			settings = {
				-- A project's own ruff.toml/pyproject.toml wins over these.
				configurationPreference = "filesystemFirst",
				lineLength = 88,
				lint = { extendSelect = { "I", "UP", "B", "SIM" } },
			},
		},
		on_attach = function(client)
			client.server_capabilities.hoverProvider = false
			client.server_capabilities.definitionProvider = false
		end,
	},
	ty = {
		settings = {
			ty = {
				-- Workspace mode re-checks every file on each keystroke.
				diagnosticMode = "openFilesOnly",
				inlayHints = { variableTypes = true, callArgumentNames = true },
				completions = { autoImport = true, completeFunctionParentheses = true },
			},
		},
	},

	-- Web. svelte owns .svelte files; ts_ls only sees js/ts, and reaches into
	-- components through typescript-svelte-plugin when a project installs it.
	svelte = {},
	ts_ls = {
		settings = {
			typescript = { inlayHints = inlay_hints_ts },
			javascript = { inlayHints = inlay_hints_ts },
		},
	},
	html = {},
	cssls = {
		settings = {
			-- Tailwind's @apply/@screen are not real at-rules, and the built-in
			-- linter would flag every one of them.
			css = { lint = { unknownAtRules = "ignore" } },
			scss = { lint = { unknownAtRules = "ignore" } },
			less = { lint = { unknownAtRules = "ignore" } },
		},
	},
	jsonls = {},
	tailwindcss = {
		settings = {
			tailwindCSS = {
				classAttributes = { "class", "className", "classList", "ngClass" },
				-- Classes passed to these helpers get completion and hover too.
				classFunctions = { "cva", "cx", "cn", "clsx", "tw", "twMerge", "twJoin" },
				lint = { cssConflict = "warning", invalidApply = "error" },
			},
		},
	},
	-- Abbreviation expansion (`ul>li*3<C-y>,`-style) that none of the above do.
	emmet_language_server = {},

	rust_analyzer = {
		settings = {
			["rust-analyzer"] = {
				cargo = { buildScripts = { enable = true } },
				-- clippy on save instead of plain `cargo check`: same cost, more
				-- lints. --no-deps keeps it to this workspace.
				checkOnSave = true,
				check = { command = "clippy", extraArgs = { "--no-deps" } },
				procMacro = { enable = true },
				imports = { granularity = { group = "module" }, prefix = "self" },
				inlayHints = {
					closureReturnTypeHints = { enable = "with_block" },
					parameterHints = { enable = true },
					lifetimeElisionHints = { enable = "skip_trivial" },
				},
				files = { excludeDirs = { ".direnv", ".git", "target" } },
			},
		},
	},

	sourcekit = {
		filetypes = { "swift" },
	},

	-- Nushell ships its own server (`nu --lsp`); nu-lint adds the lint rules on
	-- top of it, as a second client on the same buffer.
	nushell = {},
	nu_lint = {
		cmd = { "nu-lint", "--lsp" },
		filetypes = { "nu" },
		root_markers = { ".git" },
	},
}

return {
	{
		"nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		after = function()
			vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities({}, true) })
			for name, opts in pairs(servers) do
				vim.lsp.config(name, opts)
			end
			vim.lsp.enable(vim.tbl_keys(servers))

			-- Colours come from whichever server answers textDocument/documentColor
			-- (tailwind, mostly). The default style repaints the text background;
			-- "virtual" instead draws an inline 󰏘 swatch before the match.
			vim.lsp.document_color.enable(true, nil, { style = "virtual" })

			-- 0.11+ already maps grn, gra, grr, gri, gO, K and <C-s>.
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local function map(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
					end
					map("gd", Snacks.picker.lsp_definitions, "Definitions")
					map("gr", Snacks.picker.lsp_references, "References")
					map("gI", Snacks.picker.lsp_implementations, "Implementations")
					map("gy", Snacks.picker.lsp_type_definitions, "Type definitions")
					map("<leader>ss", Snacks.picker.lsp_symbols, "Document symbols")
					map("<leader>cr", vim.lsp.buf.rename, "Rename")
					map("<leader>ca", vim.lsp.buf.code_action, "Code action")
				end,
			})
		end,
	},

	-- blink builds every provider in `sources.default` to read its trigger
	-- characters, and that require runs before the provider's own enabled check,
	-- so `ft` alone leaves the module missing in every non-Lua buffer.
	{
		"lazydev.nvim",
		ft = "lua",
		on_require = "lazydev",
		after = function() require("lazydev").setup({}) end,
	},

	-- LSP progress in the bottom right. Notifications stay with snacks, so
	-- `notification.override_vim_notify` is left off.
	{
		"fidget.nvim",
		event = "LspAttach",
		after = function()
			require("fidget").setup({
				progress = {
					display = {
						done_icon = "󰄬",
						progress_icon = { pattern = "dots", period = 1 },
					},
				},
				notification = {
					window = { winblend = 0, border = require("config.ui").border },
				},
			})
		end,
	},
}

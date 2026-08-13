-- Nix puts every plugin in the wrapper's opt directory; lze packadds them on
-- the same event/keys/ft triggers lazy.nvim used, so the specs below read
-- almost exactly as they did before.
require("lze").load({
	{ import = "plugins.colourscheme" },
	{ import = "plugins.snacks" },
	{ import = "plugins.treesitter" },
	{ import = "plugins.editor" },
	{ import = "plugins.completion" },
	{ import = "plugins.lsp" },
	{ import = "plugins.format" },
	{ import = "plugins.mini" },
})

-- Shared UI constants + the theme-agnostic highlight tweaks that give the
-- picker its NvChad look. Change `border` here and every float follows.
--
-- "solid" is a border made of spaces: no visible line, but it still carries
-- window titles and doubles as a cell of padding on every side.
local M = { border = "solid" }

M.diagnostic_icons = { Error = "󰅚 ", Warn = "󰀪 ", Info = "󰋽 ", Hint = "󰌶 " }

-- How many servers are attached to this buffer, and nothing at all when none
-- are, so the section collapses instead of leaving a stray separator.
function M.lsp_indicator()
	local n = #vim.lsp.get_clients({ bufnr = 0 })
	if n == 0 then return "" end
	return n .. (n == 1 and " lsp" or " lsps")
end

local function hl(group, attr, fallback)
	local ok, def = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
	return (ok and def and def[attr]) and ("#%06x"):format(def[attr]) or fallback
end

-- Mix two "#rrggbb" strings; `ratio` is how much of `b` ends up in the result.
local function blend(a, b, ratio)
	local ca, cb, out = tonumber(a:sub(2), 16), tonumber(b:sub(2), 16), 0
	for _, shift in ipairs({ 16, 8, 0 }) do
		local x, y = bit.band(bit.rshift(ca, shift), 255), bit.band(bit.rshift(cb, shift), 255)
		out = bit.bor(out, bit.lshift(math.floor(x + (y - x) * ratio + 0.5), shift))
	end
	return ("#%06x"):format(out)
end

-- Snacks maps NormalFloat to "SnacksPicker" .. prefix with no Normal suffix,
-- so the body groups are SnacksPickerInput, not SnacksPickerInputNormal.
local function paint()
	local fg = hl("Normal", "fg", "#c0caf5")
	local base = hl("Normal", "bg", "#1a1b26")
	local float = hl("NormalFloat", "bg", base)
	local accent = hl("Function", "fg", "#7aa2f7")
	local accent2 = hl("String", "fg", "#9ece6a")
	local muted = hl("Comment", "fg", "#565f89")
	local sel = hl("Visual", "bg", "#283457")

	-- luna paints NormalFloat exactly like Normal, which left every float with
	-- no edge at all once the borders stopped drawing one. When a theme does
	-- that, lift floats a step towards the foreground instead; a theme that
	-- already distinguishes them is left alone.
	local bg = float == base and blend(base, fg, 0.06) or float
	-- The prompt row takes one more step, so it reads as its own box.
	local bar = blend(bg, fg, 0.06)

	local groups = {
		NormalFloat = { bg = bg, fg = fg },
		Pmenu = { bg = bg, fg = fg },
		WinSeparator = { fg = bg },

		SnacksNormal = { bg = bg, fg = fg },
		SnacksNormalNC = { bg = bg, fg = fg },
		SnacksWinBar = { bg = bg, fg = accent, bold = true },

		SnacksPicker = { bg = bg, fg = fg },
		SnacksPickerInput = { bg = bar, fg = fg },
		SnacksPickerInputSearch = { bg = bar, fg = accent2, bold = true },
		SnacksPickerPrompt = { bg = bar, fg = accent, bold = true },
		SnacksPickerTotals = { bg = bar, fg = muted },
		SnacksPickerList = { bg = bg, fg = fg },
		SnacksPickerPreview = { bg = bg, fg = fg },
		SnacksPickerToggleHidden = { bg = muted, fg = bg },
		SnacksPickerListCursorLine = { bg = sel, bold = true },
		SnacksPickerMatch = { fg = accent2, bold = true },
		SnacksPickerDir = { fg = muted },
		SnacksIndentScope = { fg = accent },

		-- blink links these to NormalFloat only when the theme leaves them alone;
		-- luna defines them itself, so the menu body kept the old background while
		-- the border padding followed ours. Set them outright.
		BlinkCmpMenu = { bg = bg, fg = fg },
		BlinkCmpDoc = { bg = bg, fg = fg },
		BlinkCmpDocSeparator = { bg = bg, fg = muted },
		BlinkCmpSignatureHelp = { bg = bg, fg = fg },
		BlinkCmpMenuSelection = { bg = sel, bold = true },
		BlinkCmpLabel = { bg = bg, fg = fg },
		BlinkCmpLabelDescription = { bg = bg, fg = muted },
		BlinkCmpLabelDetail = { bg = bg, fg = muted },
		-- Matched characters get weight, not a colour of their own, so they still
		-- read as part of the label on both the plain and the selected row.
		BlinkCmpLabelMatch = { bold = true },
		BlinkCmpKind = { bg = bg, fg = muted },
		BlinkCmpSource = { fg = muted, italic = true },

		FidgetTitle = { fg = accent, bold = true },
		FidgetTask = { fg = muted },

		MiniStatuslineFilename = { fg = fg },
		MiniStatuslineDevinfo = { fg = muted },
		MiniStatuslineInactive = { fg = muted },
		MiniTablineCurrent = { bg = accent, fg = bg, bold = true },
		MiniTablineVisible = { bg = bg, fg = fg },
		MiniTablineHidden = { bg = bg, fg = muted },
		MiniTablineFill = { bg = bg },
	}

	-- Borders are only ever the space cells of the `solid` border, so each one
	-- takes its own window's background and no edge colour of its own. The
	-- prompt sits on the lifted bar, everything else on the plain float.
	for group, on in pairs({
		FloatBorder = bg,
		SnacksPickerBorder = bg,
		SnacksPickerListBorder = bg,
		SnacksPickerPreviewBorder = bg,
		SnacksPickerInputBorder = bar,
		BlinkCmpMenuBorder = bg,
		BlinkCmpDocBorder = bg,
		BlinkCmpSignatureHelpBorder = bg,
	}) do
		groups[group] = { bg = on, fg = on }
	end

	-- Titles survive as centred pills on those invisible borders.
	for group, colour in pairs({
		FloatTitle = accent,
		SnacksPickerTitle = accent,
		SnacksPickerInputTitle = accent,
		SnacksPickerListTitle = accent2,
		SnacksPickerPreviewTitle = accent2,
	}) do
		groups[group] = { bg = colour, fg = bg, bold = true }
	end

	-- which-key and blink resolve their groups against NormalFloat once and bake
	-- the colour in rather than linking, so moving the float background leaves
	-- their text sitting on patches of the old one — the per-kind icon groups
	-- especially. Rewrite whichever carry it.
	local stale = tonumber(float:sub(2), 16)
	for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
		if def.bg == stale and not groups[name] and (name:find("^WhichKey") or name:find("^BlinkCmp")) then
			groups[name] = vim.tbl_extend("force", def, { bg = bg })
		end
	end

	-- Helix-style mode block: a filled pill, one colour per mode.
	for mode, colour in pairs({
		Normal = accent,
		Insert = accent2,
		Visual = hl("Keyword", "fg", "#bb9af7"),
		Replace = hl("DiagnosticError", "fg", "#f7768e"),
		Command = hl("Constant", "fg", "#e0af68"),
		Other = muted,
	}) do
		groups["MiniStatuslineMode" .. mode] = { bg = colour, fg = bg, bold = true }
	end

	for group, spec in pairs(groups) do
		vim.api.nvim_set_hl(0, group, spec)
	end
end

function M.setup()
	vim.diagnostic.config({
		severity_sort = true,
		virtual_text = { spacing = 2, prefix = "●", source = "if_many" },
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = M.diagnostic_icons.Error,
				[vim.diagnostic.severity.WARN] = M.diagnostic_icons.Warn,
				[vim.diagnostic.severity.INFO] = M.diagnostic_icons.Info,
				[vim.diagnostic.severity.HINT] = M.diagnostic_icons.Hint,
			},
		},
		float = { border = M.border, source = "if_many" },
		jump = { float = true },
	})

	vim.api.nvim_create_autocmd("ColorScheme", { callback = paint })
	paint()
end

return M

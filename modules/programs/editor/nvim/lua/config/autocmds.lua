local group = vim.api.nvim_create_augroup("cfg", { clear = true })
local function au(event, opts)
	vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", { group = group }, opts))
end

au("TextYankPost", {
	callback = function() vim.hl.on_yank({ higroup = "IncSearch", timeout = 150 }) end,
})

au("BufReadPost", {
	callback = function(ev)
		local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
		if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

au("FileType", {
	pattern = { "checkhealth", "help", "man", "qf", "query", "lspinfo" },
	callback = function(ev)
		vim.bo[ev.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = ev.buf, silent = true })
	end,
})

au("BufWritePre", {
	callback = function(ev)
		if not ev.match:match("^%w%w+:[\\/][\\/]") then
			vim.fn.mkdir(vim.fn.fnamemodify(ev.match, ":p:h"), "p")
		end
	end,
})

au({ "FocusGained", "TermClose", "TermLeave" }, {
	callback = function()
		if vim.o.buftype ~= "nofile" then vim.cmd.checktime() end
	end,
})

-- One buffer and one tab means the tabline would only ever show the file the
-- statusline already names, so hide it. Always deferred: BufDelete fires while
-- the buffer is still listed, and mini.tabline's setup pins showtabline to 2
-- when it loads on DeferredUIEnter, so this has to land after it either way.
local function fit_tabline()
	vim.schedule(function()
		local many = #vim.fn.getbufinfo({ buflisted = 1 }) > 1 or vim.fn.tabpagenr("$") > 1
		vim.o.showtabline = many and 2 or 0
	end)
end

au({ "VimEnter", "BufAdd", "BufDelete", "TabNew", "TabClosed" }, { callback = fit_tabline })
au("User", { pattern = "DeferredUIEnter", callback = fit_tabline })

-- Attaching a server does not itself trigger a statusline redraw, so the dot
-- would otherwise only appear on the next cursor move.
au({ "LspAttach", "LspDetach" }, { callback = function() vim.cmd.redrawstatus() end })

au("VimResized", {
	callback = function()
		local tab = vim.api.nvim_get_current_tabpage()
		vim.cmd("tabdo wincmd =")
		vim.api.nvim_set_current_tabpage(tab)
	end,
})

au("ColorScheme", {
	callback = function()
		vim.api.nvim_set_hl(0, "MsgArea", { link = "Normal" })
	end,
})

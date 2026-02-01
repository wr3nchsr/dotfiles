vim.o.number = true
vim.o.relativenumber = true
vim.o.wrap = false
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
vim.o.swapfile = false
vim.o.undofile = true
vim.o.clipboard = "unnamedplus"
vim.o.signcolumn = "yes"
vim.o.cursorline = true
vim.o.showmode = false
vim.o.termguicolors = true

vim.o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.o.foldmethod = "expr"
vim.o.foldlevel = 99
vim.o.foldtext = "v:lua.CustomFoldText()"

function _G.CustomFoldText()
  local first = vim.fn.getline(vim.v.foldstart)
  local lines = vim.v.foldend - vim.v.foldstart + 1
  return first .. " (" .. lines .. " lines)"
end


vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.mapleader = " "

vim.pack.add({
    { src = "https://github.com/vague-theme/vague.nvim" },

    { src = "https://github.com/alexghergh/nvim-tmux-navigation" },
    { src = "https://github.com/nvim-tree/nvim-tree.lua" },
    { src = "https://github.com/nvim-tree/nvim-web-devicons" },
    { src = "https://github.com/nvim-lualine/lualine.nvim" },

    { src = "https://github.com/ibhagwan/fzf-lua" },

    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
})

require("vague").setup({ transparent = true })
vim.cmd("colorscheme vague")

require("nvim-tree").setup()
local tslanguages = { "lua", "markdown", "json", "xml", "javascript", "c", "python", "go", "java" }
require('nvim-treesitter').install(tslanguages)
vim.api.nvim_create_autocmd("FileType", {
    pattern = tslanguages,
    callback = function()
        vim.treesitter.start()
    end,
})

require("mason").setup()
vim.api.nvim_create_autocmd('LspAttach', {
	group = vim.api.nvim_create_augroup('my.lsp', {}),
	callback = function(args)
		local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
		if client:supports_method('textDocument/completion') then
			-- Optional: trigger autocompletion on EVERY keypress. May be slow!
			local chars = {}; for i = 32, 126 do table.insert(chars, string.char(i)) end
			client.server_capabilities.completionProvider.triggerCharacters = chars
			vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
		end
	end,
})

vim.cmd("set completeopt+=menuone,noselect,popup")
vim.lsp.enable({
    "lua_ls", "clangd", "ruff", "pyright", "marksman", "asm_lsp",
    "tsserver", "intelephense", "jdtls", "gopls", "rust_analyzer", "bashls"
})


require("lualine").setup({
    options = {
        globalstatus = true,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        always_divide_middle = false,
    },
    sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { "filename" },
        lualine_x = { "selectioncount" },
        lualine_y = { "encoding", "fileformat", "filetype", "lsp_status" },
        lualine_z = {},
    },
})

require("nvim-tmux-navigation").setup({
    disable_when_zoomed = true
})

local map = vim.keymap.set

map("n", "<C-h>", "<CMD>NvimTmuxNavigateLeft<CR>")
map("n", "<C-j>", "<CMD>NvimTmuxNavigateDown<CR>")
map("n", "<C-k>", "<CMD>NvimTmuxNavigateUp<CR>")
map("n", "<C-l>", "<CMD>NvimTmuxNavigateRight<CR>")
map("n", "<C-\\>", "<CMD>NvimTmuxNavigateLastActive<CR>")
map("n", "<C-Space>", "<CMD>NvimTmuxNavigateNext<CR>")

map("n", "<leader>ff", "<CMD>FzfLua files<CR>")
map("n", "<leader>fg", "<CMD>FzfLua live_grep<CR>")
map("n", "<leader>fr", "<CMD>FzfLua oldfiles<CR>")

map("n", "<leader>sh", "<CMD>split<CR>")
map("n", "<leader>sv", "<CMD>vsplit<CR>")
map("n", "<leader>x", "<CMD>bd<CR>")
map("n", "<leader>q", "<CMD>q<CR>")
map("n", "<leader>t", "<CMD>NvimTreeToggle<CR>")

map("n", "<leader>bf", vim.lsp.buf.format)
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")


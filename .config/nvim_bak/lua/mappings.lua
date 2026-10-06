require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map({"n", "v", "i"}, "<c-h>", "<cmd>TmuxNavigateLeft<cr>")
map({"n", "v", "i"}, "<c-j>", "<cmd>TmuxNavigateDown<cr>")
map({"n", "v", "i"}, "<c-k>", "<cmd>TmuxNavigateUp<cr>")
map({"n", "v", "i"}, "<c-l>", "<cmd>TmuxNavigateRight<cr>")
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

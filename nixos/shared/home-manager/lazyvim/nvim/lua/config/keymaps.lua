-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set({ "n", "v", "s", "x", "o", "i", "l", "c", "t" }, "<C-S-v>", function()
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end, { noremap = true, silent = true })

-- Neovide font size adjustment
if vim.g.neovide then
  local function adjust_font_size(delta)
    local guifont = vim.o.guifont
    local font, size = guifont:match("(.+):h(%d+)")
    if font and size then
      local new_size = math.max(1, tonumber(size) + delta)
      vim.o.guifont = font .. ":h" .. new_size
    end
  end

  vim.keymap.set({ "n", "v", "i" }, "<C-=>", function()
    adjust_font_size(1)
  end, { noremap = true, silent = true, desc = "Increase font size" })

  vim.keymap.set({ "n", "v", "i" }, "<C-->", function()
    adjust_font_size(-1)
  end, { noremap = true, silent = true, desc = "Decrease font size" })
end

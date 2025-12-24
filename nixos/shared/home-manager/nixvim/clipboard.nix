{
  # The settings below support copying over SSH using OSC 52.
  #
  # Paste is not supported by using 'p' or 'P' in normal mode over ssh,
  # but can use CTRL+SHIFT+V in insert mode to paste the clipboard content.
  programs.nixvim.extraConfigLuaPre = ''
    if vim.env.SSH_TTY then
      local function paste()
        return {
          vim.fn.split(vim.fn.getreg("", 1), "\n"),
          vim.fn.getregtype "",
        }
      end

      vim.g.clipboard = {
        name = "OSC 52",
        copy = {
          ["+"] = require("vim.ui.clipboard.osc52").copy "+",
          ["*"] = require("vim.ui.clipboard.osc52").copy "*",
        },
        paste = {
          ["+"] = paste,
          ["*"] = paste,
        },
      }
    end
  '';
}

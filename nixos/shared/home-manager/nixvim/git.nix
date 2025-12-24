{
  programs.nixvim.extraFiles."after/ftplugin/gitcommit.lua".text = # lua
    ''
      -- Disable annoying automatic text wrapping
      vim.opt_local.formatoptions:remove { "t", "l" }
    '';
}

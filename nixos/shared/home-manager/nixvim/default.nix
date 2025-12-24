{
  inputs,
  pkgs,
  osConfig,
  ...
}:
{
  imports = [
    inputs.nixvim.homeModules.nixvim

    ./autocmds.nix
    ./clipboard.nix
    ./keymaps.nix
    ./neovide.nix
    ./opts.nix
    ./git.nix
    # ./plugins
  ];
  programs.nixvim = {
    enable = true;
    nixpkgs.pkgs = pkgs;
    defaultEditor = true;
    package = osConfig.programs.neovim.package;
    # package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
    extraPackages = with pkgs; [
      ripgrep
      fd
      wgo
    ];
    extraConfigLuaPre = # lua
      ''
        -- Space key has to be set to NOP for setting leader key to space to work.
        vim.keymap.set("", "<Space>", "<Nop>", {})
      '';
    globals = {
      # Set leader key to space.
      mapleader = " ";
      maplocalleader = "\\";
    };
  };
}

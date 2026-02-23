{ config, pkgs, ... }:
{
  imports = [ ./go.nix ];

  programs.neovim.enable = true;
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/lazyvim/nvim";
  home.packages = with pkgs; [
    cargo
    lsof
    statix
    typescript-go
    biome
  ];
}

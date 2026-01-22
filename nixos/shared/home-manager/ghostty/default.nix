{ config, pkgs, ... }:
{
  home.packages = with pkgs; [ ghostty ];
  xdg.configFile."ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/ghostty/ghostty";
}

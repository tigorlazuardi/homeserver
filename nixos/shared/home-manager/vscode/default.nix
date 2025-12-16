{ config, pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      # Nix IDE
      jnoortheen.nix-ide

      # Catppuccin Theme
      catppuccin.catppuccin-vsc
      catppuccin.catppuccin-vsc-icons

      # claude-code
      # anthropic.claude-code

      # vim motions
      vscodevim.vim

      # Sops support
      signageos.signageos-vscode-sops

      golang.go
    ];
  };

  xdg.configFile."Code/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/vscode/settings.json";
}

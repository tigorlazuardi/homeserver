{ config, pkgs, ... }:
{
  programs.zed-editor = {
    enable = true;
    extensions = [
      "catppuccin-blur"
      "catppuccin-blur-plus"
      "catppuccin-icons"
      "comment"
      "dbml"
      "docker"
      "emmet"
      "fish"
      "git-firefly"
      "hocon"
      "http"
      "json5"
      "jsonl"
      "live-server"
      "lua"
      "make"
      "nix"
      "svelte"
      "toml"

      "tsgo"
    ];
    installRemoteServer = true;
  };

  home.packages = with pkgs; [
    nixd
    zed-editor
    nodejs
  ];

  xdg.configFile."zed".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/zed/zed";
}

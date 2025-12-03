{ config, pkgs, ... }:
{
  programs.zed-editor = {
    enable = true;
    extensions = [
      "catppuccin-blur"
      "catppuccin-icons"
      "comment"
      "dbml"
      "docker"
      "emmet"
      "fish"
      "gitlab-ci-ls"
      "hocon"
      "http"
      "json5"
      "jsonl"
      "live-server"
      "lua"
      "make"
      "nix"
      "toml"

      "tsgo"
    ];
    installRemoteServer = true;
  };

  home.packages = with pkgs; [
    nixd
    zed-editor
  ];

  xdg.configFile."zed".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/zed/zed";
}

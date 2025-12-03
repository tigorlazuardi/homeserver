{ ... }:
{
  imports = [
    ../../shared/home-manager/git.nix
    ../../shared/home-manager/zed
  ];

  home.stateVersion = "25.11";
  home.username = "homeserver";
  home.homeDirectory = "/home/homeserver";
}

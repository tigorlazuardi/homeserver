{ ... }:
{
  imports = [
    ../../shared/home-manager/git.nix
    ../../shared/home-manager/lazygit.nix
    ../../shared/home-manager/bun.nix
    # ../../shared/home-manager/zed
    ../../shared/home-manager/pi-coding-agent

    ../../environments/open-code/home-manager
  ];

  home.stateVersion = "25.11";
  home.username = "homeserver";
  home.homeDirectory = "/home/homeserver";
}

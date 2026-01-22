{
  osConfig,
  ...
}:
{
  imports = [
    ../../environments/aldhyaksa/home-manager
    ../../environments/bareksa/home-manager
    ../../environments/claude-code/home-manager
    ../../environments/open-code/home-manager
    ../../environments/grandboard/home-manager

    ../../shared/home-manager/flatpak
    ../../shared/home-manager/vivaldi.nix
    ../../shared/home-manager/git.nix
    ../../shared/home-manager/lazygit.nix
    ../../shared/home-manager/vscode
    ../../shared/home-manager/zed
    ../../shared/home-manager/neovide.nix
    ../../shared/home-manager/ghostty

    ./ssh.nix
  ];

  # KDE Connect indicator in system tray (enabled if NixOS level is enabled)
  services.kdeconnect = {
    enable = osConfig.programs.kdeconnect.enable;
    indicator = true;
  };

  home.stateVersion = "25.11";
  home.username = "tigor";
  home.homeDirectory = "/home/tigor";
}

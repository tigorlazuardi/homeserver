{ osConfig, ... }:
{
  imports = [
    ../../environments/claude-code/home-manager
    ../../shared/home-manager/flatpak/slack.nix
    ../../shared/home-manager/flatpak/vesktop.nix
    ../../shared/home-manager/flatpak/whatsapp.nix
    ../../shared/home-manager/git.nix

    ./flatpak.nix
  ];

  # KDE Connect indicator in system tray (enabled if NixOS level is enabled)
  services.kdeconnect = {
    enable = osConfig.programs.kdeconnect.enable;
    indicator = true;
  };

  home.stateVersion = "25.11";
}

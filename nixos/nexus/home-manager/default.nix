{
  imports = [
    ../../shared/home-manager/flatpak/slack.nix
    ../../shared/home-manager/flatpak/vesktop.nix
    ../../shared/home-manager/flatpak/whatsapp.nix

    ./flatpak.nix
  ];

  home.stateVersion = "25.11";
}

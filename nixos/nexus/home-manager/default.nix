{
  inputs,
  osConfig,
  config,
  ...
}:
{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak

    ../../environments/aldhyaksa/home-manager
    ../../environments/bareksa/home-manager
    ../../environments/claude-code/home-manager
    ../../shared/home-manager/flatpak/slack.nix
    ../../shared/home-manager/flatpak/vesktop.nix
    ../../shared/home-manager/flatpak/whatsapp.nix
    ../../shared/home-manager/git.nix
    ../../shared/home-manager/vscode
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

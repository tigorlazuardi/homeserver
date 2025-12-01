{ pkgs, ... }:
{
  # Enable X11 and KDE Plasma 6
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;

  # # XDG portal for Wayland
  # xdg.portal = {
  #   enable = true;
  #   extraPortals = [ pkgs.xdg-desktop-portal-kde ];
  # };

  # Audio with PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Common KDE applications
  environment.systemPackages = with pkgs; [
    kdePackages.kate
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.kcalc
    kdePackages.skanpage

    # Archive tools for Dolphin/Ark integration (right-click compress/extract)
    p7zip
    unrar
    zip
    unzip

    # KDE Discover for Flatpak
    kdePackages.discover
    kdePackages.packagekit-qt
  ];

  # Enable Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # KDE Connect for phone integration
  programs.kdeconnect.enable = true;
}

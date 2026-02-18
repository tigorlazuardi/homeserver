{ pkgs, ... }:
{
  boot.loader = {
    systemd-boot.enable = false; # we will dual boot between NixOS and Windows
    grub = {
      enable = true;
      useOSProber = true;
      efiSupport = true;
      device = "nodev";
      configurationLimit = 50;
      theme = pkgs.catppuccin-grub;
    };
  };
}

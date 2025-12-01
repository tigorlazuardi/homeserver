{ pkgs, ... }:
{
  # CUPS printing service
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # Auto-discovery of network printers
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}

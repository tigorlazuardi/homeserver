{ pkgs, ... }:
{
  networking = {
    usePredictableInterfaceNames = false;
    networkmanager.enable = true;
    hostName = "nexus";
    enableIPv6 = false;
    hosts = {
      "192.168.100.50" = [ "homeserver" ];
    };
    firewall.allowedTCPPorts = [ 5173 ]; # vite
  };

  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  users.users.tigor.extraGroups = [ "networkmanager" ];
}

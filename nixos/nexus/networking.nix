{ pkgs, ... }:
{
  networking = {
    usePredictableInterfaceNames = false;
    networkmanager.enable = true;
    hostName = "nexus";
    enableIPv6 = false;
  };

  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  users.users.tigor.extraGroups = [ "networkmanager" ];
}

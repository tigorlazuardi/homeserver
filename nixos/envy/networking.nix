{ pkgs, ... }:
{
  networking = {
    usePredictableInterfaceNames = false;
    networkmanager.enable = true;
    hostName = "envy";
    enableIPv6 = false;
  };

  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  networking.firewall.allowedTCPPorts = [
    5173 # vite
  ];

  users.users.tigor.extraGroups = [ "networkmanager" ];
}

{
  networking = {
    usePredictableInterfaceNames = false;
    networkmanager.enable = true;
    hostName = "nexus";
    enableIPv6 = false;
  };

  users.users.tigor.extraGroups = [ "networkmanager" ];
}

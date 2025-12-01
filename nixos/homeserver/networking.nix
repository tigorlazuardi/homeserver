{
  # Unless we have multiple network cards, we don't need this to be true.
  networking.usePredictableInterfaceNames = false;
  networking.networkmanager.enable = true;
  users.users.homeserver = {
    extraGroups = [ "networkmanager" ];
    authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
    ];
  };
  networking.hostName = "homeserver";
  networking.enableIPv6 = false;
}

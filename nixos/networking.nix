{
  # Unless we have multiple network cards, we don't need this to be true.
  networking.usePredictableInterfaceNames = false;
  networking.networkmanager.enable = true;
  users.users.homeserver.extraGroups = [ "networkmanager" ];
}


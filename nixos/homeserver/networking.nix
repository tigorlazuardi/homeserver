{
  # Unless we have multiple network cards, we don't need this to be true.
  networking.usePredictableInterfaceNames = false;

  users.users.homeserver = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
    ];
  };

  # Use scripted networking (DHCP via dhcpcd)
  networking.interfaces.eth0.useDHCP = true;

  networking.hostName = "homeserver";
  networking.enableIPv6 = false;
}

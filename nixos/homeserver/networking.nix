{
  # Unless we have multiple network cards, we don't need this to be true.
  networking.usePredictableInterfaceNames = false;
  networking.useNetworkd = true;

  users.users.homeserver = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
    ];
  };

  systemd.network = {
    enable = true;
    networks."25-wired" = {
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "ipv4";
      linkConfig.RequiredForOnline = "routable";
    };
  };

  networking.hostName = "homeserver";
  networking.enableIPv6 = false;

  # Allow binding to low ports without CAP_NET_BIND_SERVICE.
  #
  # Since we will run podman containers in homeserver namespace (rootless),
  # we need this to allow binding to low ports like 80 and 443.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 0;
}

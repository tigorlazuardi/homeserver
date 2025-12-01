{
  # Despite being open, this port will not be accessible from the internet via direct connections since the router
  # will block it.
  #
  # To connect to this server outside of local network, client must use wireguard VPN first.
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh.enable = true;
}

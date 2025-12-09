{
  # Unless we have multiple network cards, we don't need this to be true.
  networking.usePredictableInterfaceNames = false;

  # Use scripted networking (DHCP via dhcpcd)
  networking.interfaces.eth0.useDHCP = true;

  networking.hostName = "homeserver";
  networking.enableIPv6 = false;
}

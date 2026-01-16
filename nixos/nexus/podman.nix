{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };
}

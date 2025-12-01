{
  users.users.homeserver = {
    isNormalUser = true;
    initialPassword = "ganti"; # ganti dengan passwd
    extraGroups = [ "wheel" ];
  };
}

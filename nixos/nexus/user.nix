{
  sops.secrets."users/tigor/password" = {
    neededForUsers = true;
    sopsFile = ../../secrets/users.yaml;
  };

  users.users.tigor = {
    isNormalUser = true;
    initialPassword = "ganti"; # ganti dengan passwd
    extraGroups = [
      "wheel"
      "tigor"
    ];
  };
  users.groups.tigor = { };
}

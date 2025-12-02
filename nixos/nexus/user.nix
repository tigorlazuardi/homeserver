{ config, pkgs, ... }:
{
  sops.secrets."users/tigor/password" = {
    neededForUsers = true;
    sopsFile = ../../secrets/users.yaml;
  };

  users.users.tigor = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets."users/tigor/password".path;
    extraGroups = [
      "wheel"
      "tigor"
    ];
    shell = pkgs.fish;
  };
  users.groups.tigor = { };
}

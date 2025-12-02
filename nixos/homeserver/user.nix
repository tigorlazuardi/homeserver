{ config, pkgs, ... }:
{
  sops.secrets."users/homeserver/password" = {
    neededForUsers = true;
    sopsFile = ../../secrets/users.yaml;
  };
  users.users.homeserver = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets."users/homeserver/password".path;
    extraGroups = [
      "wheel"
      "homeserver"
    ];
    shell = pkgs.fish;
  };
  users.groups.homeserver = { };
}

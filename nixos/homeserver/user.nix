{ config, pkgs, ... }:
{
  imports = [
    ../shared/fish/system.nix
  ];
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
    linger = true; # Allow user services to run when not logged in
  };
  users.groups.homeserver = { };
}

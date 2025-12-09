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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUdNT+Pr015Li6Jp9cb1vCghd2C8EnecYwSC98qQCxl tigor@envy"
    ];
  };
  users.groups.homeserver = { };
}

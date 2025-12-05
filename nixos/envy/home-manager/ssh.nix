{ config, ... }:
{
  sops.secrets = {
    "ssh/private_key" = {
      sopsFile = ./ssh.yaml;
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
    "ssh/public_key" = {
      sopsFile = ./ssh.yaml;
      path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };
  };
}

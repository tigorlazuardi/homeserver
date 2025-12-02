{ config, ... }:
{
  sops.secrets = {
    "ssh/public_key" = {
      sopsFile = ./ssh.yaml;
      key = "public";
      path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };
    "ssh/private_key" = {
      sopsFile = ./ssh.yaml;
      key = "private";
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };
}

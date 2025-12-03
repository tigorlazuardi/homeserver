{ config, ... }:
let
  domain = "auth.grandboard.web.id";
in
{
  sops.secrets."grandboard/tinyauth.env" = {
    sopsFile = ./tinyauth.env;
    format = "dotenv";
    key = "";
  };
  virtualisation.oci-containers.containers.grandboard-tinyauth = {
    image = "ghcr.io/steveiliop56/tinyauth:v4";
    ip = "10.88.11.3";
    httpPort = 3000;
    autoUpdate.enable = true;
    environment = {
      APP_TITLE = "GrandBoard";
      APP_URL = "https://${domain}";
      OAUTH_AUTO_REDIRECT = "github";
      SECURE_COOKIES = "true";
    };
    environmentFiles = [ config.sops.secrets."grandboard/tinyauth.env".path ];
    volumes = [
      "/var/mnt/state/grandboard/tinyauth/data:/data"
    ];
  };
  systemd.services."podman-grandboard-tinyauth".preStart = ''
    mkdir -p /var/mnt/state/grandboard/tinyauth/data
  '';
}

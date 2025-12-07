{ config, ... }:
let
  domain = "auth.grandboard.web.id";
  name = "grandboard-tinyauth";
  inherit (config.virtualisation.oci-containers.containers."${name}") ip httpPort;
in
{
  sops.secrets."grandboard/tinyauth.env" = {
    sopsFile = ./tinyauth.env;
    format = "dotenv";
    key = "";
  };
  virtualisation.oci-containers.containers."${name}" = {
    image = "ghcr.io/steveiliop56/tinyauth:v4";
    ip = "10.88.11.3";
    httpPort = 3000;
    autoUpdate.enable = true;
    environment = {
      APP_TITLE = "Grand Board";
      APP_URL = "https://${domain}";
      # OAUTH_AUTO_REDIRECT = "github";
      SECURE_COOKIES = "true";
    };
    environmentFiles = [ config.sops.secrets."grandboard/tinyauth.env".path ];
    volumes = [
      "/var/mnt/state/grandboard/tinyauth/data:/data"
    ];
  };
  systemd.services."podman-grandboard-tinyauth" = {
    preStart = ''
      mkdir -p /var/mnt/state/grandboard/tinyauth/data
    '';
  };
  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
    locations."/".proxyPass = "http://${ip}:${toString httpPort}";
  };
}

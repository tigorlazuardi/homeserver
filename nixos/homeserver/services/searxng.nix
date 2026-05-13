# SearXNG - Privacy-respecting metasearch engine
# https://docs.searxng.org/admin/installation-docker.html
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.searxng-core) ip httpPort;
  domain = "searxng.tigor.web.id";
  mountDir = "/var/mnt/state/searxng";
in
{
  virtualisation.oci-containers.containers.searxng-core = {
    image = "docker.io/searxng/searxng:latest";
    ip = "10.88.1.22";
    httpPort = 8080;
    autoStart = true;
    autoUpdate.enable = true;
    volumes = [
      "${mountDir}/core-config:/etc/searxng:Z"
      "${mountDir}/core-data:/var/cache/searxng"
    ];
    environment = {
      TZ = "Asia/Jakarta";
      # Connect to Valkey container for limiter/bot-detection features
      SEARXNG_REDIS__URL = "redis://searxng-valkey:6379/0";
    };
  };

  virtualisation.oci-containers.containers.searxng-valkey = {
    image = "docker.io/valkey/valkey:9-alpine";
    autoStart = true;
    autoUpdate.enable = true;
    cmd = [ "valkey-server" "--save" "30" "1" "--loglevel" "warning" ];
    volumes = [
      "${mountDir}/valkey-data:/data"
    ];
  };

  systemd.services.podman-searxng-core.preStart = ''
    mkdir -p ${mountDir}/core-config ${mountDir}/core-data ${mountDir}/valkey-data
    chown -R 977:977 ${mountDir}/core-config ${mountDir}/core-data
    chown -R 999:999 ${mountDir}/valkey-data
  '';

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };
}

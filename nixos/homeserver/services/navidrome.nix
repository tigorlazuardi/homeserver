# Navidrome - Modern Music Server and Streamer
# https://www.navidrome.org/docs/installation/docker/
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.navidrome) ip httpPort;
  domain = "navidrome.tigor.web.id";
  dataDir = "/var/mnt/state/navidrome";
  musicDir = "/var/mnt/nas/Syncthing/Sync/Music";
in
{
  virtualisation.oci-containers.containers.navidrome = {
    image = "deluan/navidrome:latest";
    ip = "10.88.1.11";
    httpPort = 4533;
    autoStart = true;
    user = "1000:1000";
    volumes = [
      "${dataDir}:/data"
      "${musicDir}:/music:ro"
    ];
    environment = {
      TZ = "Asia/Jakarta";
      ND_SCANSCHEDULE = "1h";
      ND_LOGLEVEL = "info";
      ND_SESSIONTIMEOUT = "24h";
      ND_BASEURL = "";
    };
  };

  systemd.services.podman-navidrome.preStart = ''
    mkdir -p ${dataDir}
    chown 1000:1000 ${dataDir}
  '';

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };
}

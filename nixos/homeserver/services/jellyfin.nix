# Jellyfin - Media Server
# https://jellyfin.org/docs/general/installation/container
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.jellyfin) ip httpPort;
  domain = "jellyfin.tigor.web.id";
  configDir = "/var/mnt/state/jellyfin/config";
  cacheDir = "/var/mnt/state/jellyfin/cache";
in
{
  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    ip = "10.88.1.12";
    httpPort = 8096;
    autoStart = true;
    volumes = [
      "${configDir}:/config"
      "${cacheDir}:/cache"
      "/var/mnt/nas:/media/nas:z"
      "/var/mnt/wolf:/media/wolf:z"
    ];
    devices = [
      "/dev/dri:/dev/dri"
    ];
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "Asia/Jakarta";
      JELLYFIN_PublishedServerUrl = "https://${domain}";
    };
  };

  systemd.services.podman-jellyfin = {
    preStart = ''
      mkdir -p ${configDir} ${cacheDir}
      chown -R 1000:1000 /var/mnt/state/jellyfin
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };
}

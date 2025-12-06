# Suwayomi - Free and open source manga reader server
# https://github.com/Suwayomi/Suwayomi-Server
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.suwayomi) ip httpPort;
  domain = "manga.tigor.web.id";
  dataDir = "/var/mnt/state/suwayomi/files";
  downloadsDir = "/var/mnt/wolf/suwayomi/downloads";
in
{
  virtualisation.oci-containers.containers.suwayomi = {
    image = "ghcr.io/suwayomi/suwayomi-server:stable";
    ip = "10.88.1.13";
    httpPort = 4567;
    autoStart = true;
    autoUpdate.enable = true;
    user = "1000:1000";
    volumes = [
      "${downloadsDir}:/home/suwayomi/.local/share/Tachidesk/downloads"
      "${dataDir}:/home/suwayomi/.local/share/Tachidesk"
    ];
    environment = {
      TZ = "Asia/Jakarta";
      AUTO_DOWNLOAD_CHAPTERS = "true";
      AUTO_DOWNLOAD_EXCLUDE_UNREAD = "false";
      DOWNLOAD_CONVERSIONS = builtins.toJSON {
        "image/webp" = {
          target = "image/jpeg";
          compressionLevel = 0.8;
        };
      };
      MAX_SOURCES_IN_PARALLEL = "20";
      UPDATE_EXCLUDE_UNREAD = "false";
      UPDATE_EXCLUDE_STARTED = "false";
      FLARESOLVERR_ENABLED = "true";
      FLARESOLVERR_URL = "http://flaresolverr:8191";
      EXTENSION_REPOS = builtins.toJSON [
        "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"
      ];
    };
  };

  systemd.services.podman-suwayomi = {
    preStart = ''
      mkdir -p ${dataDir} ${downloadsDir}
      chown 1000:1000 ${dataDir} ${downloadsDir}
    '';
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."/".proxyPass = "http://${ip}:${toString httpPort}";
  };
}

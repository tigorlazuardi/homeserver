# YTPTube - Web GUI for yt-dlp with support for playlists
# https://github.com/arabcoders/ytptube
{
  config,
  ...
}:
let
  inherit (config.virtualisation.oci-containers.containers.ytptube) ip httpPort;
  domain = "ytptube.tigor.web.id";
  configDir = "/var/mnt/state/ytptube/config";
  downloadsDir = "/var/mnt/wolf/mediaserver/ytptube";
in
{
  imports = [
    ./subscribe.nix
  ];
  virtualisation.oci-containers.containers.ytptube = {
    image = "ghcr.io/arabcoders/ytptube:latest";
    ip = "10.88.1.17";
    httpPort = 8081;
    autoStart = true;
    user = "1000:1000";
    volumes = [
      "${configDir}:/config:rw"
      "${downloadsDir}:/downloads:z"
    ];
    environment = {
      TZ = "Asia/Jakarta";
      YTP_MAX_WORKERS = "4";
      YTP_OUTPUT_TEMPLATE = "%(title).50s.%(ext)s";
      YTP_TEMP_DISABLED = "true";
    };
  };

  systemd.services.podman-ytptube = {
    preStart = ''
      mkdir -p ${configDir} ${downloadsDir}
      chown 1000:1000 ${configDir} ${downloadsDir}
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };

}

# JDownloader 2 - Download Manager
# https://hub.docker.com/r/jlesage/jdownloader-2
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.jdownloader) ip httpPort;
  domain = "jdownloader.tigor.web.id";
  configDir = "/var/mnt/state/jdownloader/config";
  outputDir = "/var/mnt/nas/jdownloader";
in
{
  virtualisation.oci-containers.containers.jdownloader = {
    image = "docker.io/jlesage/jdownloader-2:latest";
    ip = "10.88.1.20";
    httpPort = 5800;
    autoStart = true;
    autoUpdate.enable = true;
    volumes = [
      "${configDir}:/config"
      "${outputDir}:/output"
    ];
    environment = {
      USER_ID = "1000";
      GROUP_ID = "1000";
      TZ = "Asia/Jakarta";
    };
  };

  systemd.services.podman-jdownloader = {
    preStart = ''
      mkdir -p ${configDir} ${outputDir}
      chown -R 1000:1000 ${configDir} ${outputDir}
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
      extraConfig = ''
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_connect_timeout 86400s;
      '';
    };
  };
}

# Apprise API - Universal Notification Gateway
# https://github.com/caronc/apprise-api
{ config, ... }:
let
  mountDir = "/var/mnt/state/apprise";
in
{
  sops.secrets."apprise.env" = {
    sopsFile = ./apprise.env;
    format = "dotenv";
    key = "";
  };

  virtualisation.oci-containers.containers.apprise = {
    image = "docker.io/caronc/apprise:latest";
    ip = "10.88.1.21";
    httpPort = 8000;
    autoStart = true;
    autoUpdate.enable = true;
    volumes = [
      "${mountDir}/config:/config"
      "${mountDir}/plugin:/plugin"
      "${mountDir}/attach:/attach"
    ];
    environment = {
      TZ = "Asia/Jakarta";
      # Attachment settings
      APPRISE_ATTACH_SIZE = "200"; # Max attachment size in MB
      APPRISE_BODY_SIZE = "65535"; # Max message body size in bytes
      # Stateless mode disabled - use persistent config
      APPRISE_STATELESS_URLS = "";
      # Worker configuration
      APPRISE_WORKER_COUNT = "1";
      APPRISE_WORKER_TIMEOUT = "300";
    };
    environmentFiles = [
      config.sops.secrets."apprise.env".path
    ];
  };

  systemd.services.podman-apprise = {
    preStart = ''
      mkdir -p ${mountDir}/config ${mountDir}/plugin ${mountDir}/attach
      chown -R 1000:1000 ${mountDir}
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

}

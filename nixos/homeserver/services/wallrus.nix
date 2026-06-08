# wallrus - Homelab wallpaper collector
# https://tigorlazuardi.github.io/wallrus/
{ config, pkgs, ... }:
let
  name = "wallrus";
  image = "ghcr.io/tigorlazuardi/wallrus:latest";
  inherit (config.virtualisation.oci-containers.containers.wallrus) ip httpPort;
  mountDir = "/var/mnt/wolf/wallrus";
in
{
  sops.secrets."wallrus.env" = {
    sopsFile = ./wallrus.env;
    format = "dotenv";
    key = "";
  };

  virtualisation.oci-containers.containers.wallrus = {
    inherit image;
    ip = "10.88.1.16";
    httpPort = 5173;
    autoUpdate.enable = true;
    volumes = [
      "${mountDir}:/data/wallrus"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      WALLRUS_LISTEN_ADDR = "0.0.0.0:5173";
      WALLRUS_TRUST_PROXY = "true";
      WALLRUS_DATA_DIR = "/data/wallrus";
      OTEL_EXPORTER_OTLP_ENDPOINT = "https://otlp.tigor.web.id";
      OTEL_RESOURCE_ATTRIBUTES = "deployment.environment.name=production,deployment.environment=production,service.namespace=wallrus";
      OTEL_SERVICE_NAME = "wallrus";
    };
    environmentFiles = [
      config.sops.secrets."wallrus.env".path
    ];
  };

  systemd.services."podman-${name}".preStart = ''
    mkdir -p ${mountDir}
    chown -R 1000:1000 ${mountDir}
  '';

  services.nginx.virtualHosts."wallrus.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };

  systemd.services."podman-${name}-update" = {
    description = "Update wallrus container";
    script = ''
      set -e
      ${pkgs.podman}/bin/podman pull ${image}
      systemctl restart podman-${name}.service
    '';
    unitConfig = {
      StartLimitIntervalSec = "30s";
      StartLimitBurst = "3";
    };
  };

  services.webhook.hooks."deploy-${name}" = {
    execute-command = "${pkgs.writeShellScript "deploy-wallrus.sh" "${pkgs.systemd}/bin/systemctl restart podman-${name}-update.service"}";
    response-message = "Wallrus deployment triggered";
  };
}

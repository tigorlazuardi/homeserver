{ config, ... }:
let
  volume = "/var/mnt/wolf/paperless-ngx";
  domain = "docs.tigor.web.id";
  inherit (config.virtualisation.oci-containers.containers.paperless-ngx)
    ip
    httpPort
    ;
  redis = {
    inherit (config.virtualisation.oci-containers.containers.paperless-redis) ip;
  };
  proxyPass = "http://${ip}:${toString httpPort}";
in
{
  sops.secrets."paperless-ngx.env" = {
    sopsFile = ./paperless-ngx.env;
    format = "dotenv";
    key = "";
  };
  virtualisation.oci-containers.containers.paperless-ngx = {
    image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
    ip = "10.88.1.10";
    httpPort = 8000;
    volumes = [
      "${volume}/data:/usr/src/paperless/data"
      "${volume}/media:/usr/src/paperless/media"
      "${volume}/export:/usr/src/paperless/export"
      "${volume}/consume:/usr/src/paperless/consume"
    ];
    environment = {
      PAPERLESS_REDIS = "redis://${redis.ip}:6379";
      USERMAP_UID = "1000"; # Allow reading files created by the user running the container
      USERMAP_GID = "1000"; # Allow reading files created by the user running the container
      PAPERLESS_URL = "https://${domain}";
      PAPERLESS_TIME_ZONE = "Asia/Jakarta";
      PAPERLESS_OCR_LANGUAGE = "ind"; # Set the default OCR language to Indonesian
      PAPERLESS_OCR_LANGUAGES = "ind"; # Ensure to install Indonesian language pack
      PAPERLESS_USE_X_FORWARD_HOST = "true";
      PAPERLESS_USE_X_FORWARD_PORT = "true";
      PAPERLESS_PROXY_SSL_HEADER = ''["HTTP_X_FORWARDED_PROTO", "https"]'';
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${domain},https://auth.tigor.web.id";
      PAPERLESS_ALLOWED_HOSTS = "${domain},auth.tigor.web.id";
      PAPERLESS_CORS_ALLOWED_HOSTS = "https://${domain},https://auth.tigor.web.id";
    };
    environmentFiles = [
      config.sops.secrets."paperless-ngx.env".path
    ];
  };
  systemd.services.podman-paperless-ngx.preStart = ''
    mkdir -p ${volume}/{data,media,export,consume}
  '';
  virtualisation.oci-containers.containers.paperless-redis = {
    image = "docker.io/library/redis:8";
    ip = "10.88.1.9";
    volumes = [
      "${volume}/redis:/data"
    ];
  };
  systemd.services.podman-paperless-redis.preStart = ''
    mkdir -p ${volume}/redis
  '';
  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    locations."/".proxyPass = proxyPass;
  };
  # services.homepage-dashboard.groups.Media.services."Paperless NGX".settings = {
  #   description = "Document storage and management system";
  #   href = "https://${domain}";
  #   icon = "paperless-ngx.svg";
  # };
}

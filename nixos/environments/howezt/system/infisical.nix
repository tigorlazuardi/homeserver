{
  config,
  lib,
  ...
}:
let
  domain = "infisical.howezt.com";
  volume = "/var/mnt/state/howezt/infisical";
  version = "v0.158.4";

  postgres = {
    inherit (config.virtualisation.oci-containers.containers.infisical-postgres) ip;
    port = 5432;
    user = "infisical";
    db = "infisical";
  };

  redis = {
    inherit (config.virtualisation.oci-containers.containers.infisical-redis) ip;
    port = 6379;
  };

  backend = {
    inherit (config.virtualisation.oci-containers.containers.infisical) ip httpPort;
  };
in
{
  sops.secrets."howezt/infisical.env" = {
    sopsFile = ./infisical.env;
    format = "dotenv";
    key = "";
  };

  # PostgreSQL for Infisical
  virtualisation.oci-containers.containers.infisical-postgres = {
    image = "docker.io/postgres:14-alpine";
    ip = "10.88.7.1";
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/postgres:/var/lib/postgresql/data"
    ];
    environment = {
      POSTGRES_USER = postgres.user;
      POSTGRES_DB = postgres.db;
    };
    environmentFiles = [
      config.sops.secrets."howezt/infisical.env".path
    ];
    extraOptions = [
      "--health-cmd=pg_isready -U ${postgres.user}"
      "--health-startup-cmd=pg_isready -U ${postgres.user}"
      "--health-startup-interval=1s"
      "--health-startup-retries=30"
    ];
  };
  systemd.services.podman-infisical-postgres.preStart = ''
    mkdir -p ${volume}/postgres
  '';

  # Redis for Infisical
  virtualisation.oci-containers.containers.infisical-redis = {
    image = "docker.io/redis:7-alpine";
    ip = "10.88.7.2";
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/redis:/data"
    ];
    environment = {
      ALLOW_EMPTY_PASSWORD = "yes";
    };
    extraOptions = [
      "--health-cmd=redis-cli ping"
      "--health-startup-cmd=redis-cli ping"
      "--health-startup-interval=1s"
      "--health-startup-retries=30"
    ];
  };
  systemd.services.podman-infisical-redis.preStart = ''
    mkdir -p ${volume}/redis
  '';

  # Infisical Backend
  virtualisation.oci-containers.containers.infisical = {
    image = "docker.io/infisical/infisical:${version}";
    ip = "10.88.7.3";
    httpPort = 8080;
    podman.sdnotify = "healthy";
    dependsOn = [
      "infisical-postgres"
      "infisical-redis"
    ];
    environment = {
      NODE_ENV = "production";
      SITE_URL = "https://${domain}";
      # DB_CONNECTION_URI is set in infisical.env with password
      REDIS_URL = "redis://${redis.ip}:${toString redis.port}";
      # Telemetry
      TELEMETRY_ENABLED = "false";
    };
    environmentFiles = [
      config.sops.secrets."howezt/infisical.env".path
    ];
    extraOptions = [
      "--health-cmd=wget --spider -q localhost:8080/api/status"
      "--health-startup-cmd=wget --spider -q localhost:8080/api/status"
      "--health-startup-interval=2s"
      "--health-startup-retries=60"
    ];
  };
  systemd.services.podman-infisical = {
    after = [
      "podman-infisical-postgres.service"
      "podman-infisical-redis.service"
    ];
    requires = [
      "podman-infisical-postgres.service"
      "podman-infisical-redis.service"
    ];
  };

  # ACME certificate for howezt.com
  security.acme.certs."howezt.com" = {
    webroot = "/var/lib/acme/acme-challenge";
    group = "nginx";
    extraDomainNames = [
      domain
    ];
  };

  services.nginx.virtualHosts = {
    "${domain}" = {
      forceSSL = true;
      useACMEHost = "howezt.com";
      locations."/" = {
        proxyPass = "http://${backend.ip}:${toString backend.httpPort}";
        extraConfig = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };
}

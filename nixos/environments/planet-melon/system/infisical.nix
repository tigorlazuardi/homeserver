{
  config,
  lib,
  ...
}:
let
  namespace = "planet-melon";
  domain = "infisical.planetmelon.space";
  volume = "/var/mnt/state/planet-melon/infisical";
  version = "v0.158.4";

  containerName = name: "infisical-${namespace}-${name}";
  serviceName = name: "podman-${containerName name}";

  postgres = {
    name = containerName "postgres";
    inherit (config.virtualisation.oci-containers.containers.${postgres.name}) ip;
    port = 5432;
    user = "infisical";
    db = "infisical";
  };

  redis = {
    name = containerName "redis";
    inherit (config.virtualisation.oci-containers.containers.${redis.name}) ip;
    port = 6379;
  };

  backend = {
    name = containerName "backend";
    inherit (config.virtualisation.oci-containers.containers.${backend.name}) ip httpPort;
  };
in
{
  sops.secrets."${namespace}/infisical.env" = {
    sopsFile = ./infisical.env;
    format = "dotenv";
    key = "";
  };

  # PostgreSQL for Infisical
  virtualisation.oci-containers.containers.${postgres.name} = {
    image = "docker.io/postgres:14-alpine";
    ip = "10.88.8.1";
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/postgres:/var/lib/postgresql/data"
    ];
    environment = {
      POSTGRES_USER = postgres.user;
      POSTGRES_DB = postgres.db;
    };
    environmentFiles = [
      config.sops.secrets."${namespace}/infisical.env".path
    ];
    extraOptions = [
      "--health-cmd=pg_isready -U ${postgres.user}"
      "--health-startup-cmd=pg_isready -U ${postgres.user}"
      "--health-startup-interval=1s"
      "--health-startup-retries=30"
    ];
  };
  systemd.services.${serviceName "postgres"}.preStart = ''
    mkdir -p ${volume}/postgres
  '';

  # Redis for Infisical
  virtualisation.oci-containers.containers.${redis.name} = {
    image = "docker.io/redis:7-alpine";
    ip = "10.88.8.2";
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
  systemd.services.${serviceName "redis"}.preStart = ''
    mkdir -p ${volume}/redis
  '';

  # Infisical Backend
  virtualisation.oci-containers.containers.${backend.name} = {
    image = "docker.io/infisical/infisical:${version}";
    ip = "10.88.8.3";
    httpPort = 8080;
    podman.sdnotify = "healthy";
    dependsOn = [
      postgres.name
      redis.name
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
      config.sops.secrets."${namespace}/infisical.env".path
    ];
    extraOptions = [
      "--health-cmd=wget --spider -q localhost:8080/api/status"
      "--health-startup-cmd=wget --spider -q localhost:8080/api/status"
      "--health-startup-interval=2s"
      "--health-startup-retries=60"
    ];
  };
  systemd.services.${serviceName "backend"} = {
    after = [
      "${serviceName "postgres"}.service"
      "${serviceName "redis"}.service"
    ];
    requires = [
      "${serviceName "postgres"}.service"
      "${serviceName "redis"}.service"
    ];
  };

  security.acme.certs."planetmelon.space".extraDomainNames = [
    domain
  ];

  services.nginx.virtualHosts = {
    "${domain}" = {
      forceSSL = true;
      useACMEHost = "planetmelon.space";
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

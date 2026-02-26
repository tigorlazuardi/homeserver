{
  config,
  lib,
  ...
}:
let
  namespace = "planet-melon";
  domain = "vikunja.planetmelon.space";
  volume = "/var/mnt/state/planet-melon/vikunja";
  version = "0.24.6";

  containerName = name: "vikunja-${namespace}-${name}";
  serviceName = name: "podman-${containerName name}";

  postgres = {
    name = containerName "postgres";
    inherit (config.virtualisation.oci-containers.containers.${postgres.name}) ip;
    port = 5432;
    user = "vikunja";
    db = "vikunja";
  };

  app = {
    name = containerName "app";
    inherit (config.virtualisation.oci-containers.containers.${app.name}) ip httpPort;
  };
in
{
  sops.secrets."${namespace}/vikunja.env" = {
    sopsFile = ./vikunja.env;
    format = "dotenv";
    key = "";
  };

  # PostgreSQL for Vikunja
  virtualisation.oci-containers.containers.${postgres.name} = {
    image = "docker.io/postgres:17-alpine";
    ip = "10.88.9.1";
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/postgres:/var/lib/postgresql/data"
    ];
    environment = {
      POSTGRES_USER = postgres.user;
      POSTGRES_DB = postgres.db;
    };
    environmentFiles = [
      config.sops.secrets."${namespace}/vikunja.env".path
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

  # Vikunja Application
  virtualisation.oci-containers.containers.${app.name} = {
    image = "docker.io/vikunja/vikunja:${version}";
    ip = "10.88.9.2";
    httpPort = 3456;
    podman.sdnotify = "healthy";
    dependsOn = [
      postgres.name
    ];
    environment = {
      VIKUNJA_SERVICE_PUBLICURL = "https://${domain}";
      VIKUNJA_SERVICE_ENABLEREGISTRATION = "false";
      VIKUNJA_SERVICE_JWTTTLLONG = "31536000"; # 1 year, for long-lived tokens (MCP, etc.)
      VIKUNJA_DATABASE_TYPE = "postgres";
      VIKUNJA_DATABASE_HOST = "${postgres.ip}:${toString postgres.port}";
      VIKUNJA_DATABASE_DATABASE = postgres.db;
      VIKUNJA_DATABASE_USER = postgres.user;
      # VIKUNJA_DATABASE_PASSWORD is set in vikunja.env
      # VIKUNJA_SERVICE_JWTSECRET is set in vikunja.env
    };
    environmentFiles = [
      config.sops.secrets."${namespace}/vikunja.env".path
    ];
    volumes = [
      "${volume}/files:/app/vikunja/files"
    ];
    extraOptions = [
      "--health-cmd=wget --spider -q localhost:3456/api/v1/info"
      "--health-startup-cmd=wget --spider -q localhost:3456/api/v1/info"
      "--health-startup-interval=2s"
      "--health-startup-retries=60"
    ];
  };
  systemd.services.${serviceName "app"} = {
    preStart = ''
      mkdir -p ${volume}/files
    '';
    after = [
      "${serviceName "postgres"}.service"
    ];
    requires = [
      "${serviceName "postgres"}.service"
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
        proxyPass = "http://${app.ip}:${toString app.httpPort}";
        extraConfig = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          client_max_body_size 20M;
        '';
      };
    };
  };
}

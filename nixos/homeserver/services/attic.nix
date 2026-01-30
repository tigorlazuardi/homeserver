{ config, pkgs, ... }:
let
  domain = "cache.tigor.web.id";
  volume = "/var/mnt/state/attic";
  inherit (config.virtualisation.oci-containers.containers.attic) ip httpPort;
  address = "http://${ip}:${toString httpPort}";
in
{
  virtualisation.oci-containers.containers.attic = {
    image = "ghcr.io/zhaofengli/attic:latest";
    ip = "10.88.5.1";
    httpPort = 8080;
    autoUpdate.enable = true;
    volumes = [
      "${volume}/server.toml:/etc/attic/server.toml:ro"
      "${volume}/storage:/var/lib/attic/storage"
    ];
    environmentFiles = [
      "${toString ./attic.env}"
    ];
    cmd = [
      "-f"
      "/etc/attic/server.toml"
    ];
  };

  systemd.services.podman-attic.preStart =
    let
      serverConfig = pkgs.writeText "server.toml" /* toml */ ''
        # Attic Server Configuration
        listen = "[::]:8080"

        # Database
        [database]
        url = "postgresql://attic:attic@attic-postgres/attic"

        # Storage
        [storage]
        type = "local"
        path = "/var/lib/attic/storage"

        # Chunking for deduplication
        [chunking]
        nar-size-threshold = 65536  # 64 KiB
        min-size = 16384            # 16 KiB
        avg-size = 65536            # 64 KiB
        max-size = 262144           # 256 KiB

        # Garbage collection
        [garbage-collection]
        interval = "12 hours"
        default-retention-period = "3 months"
      '';
    in
    # sh
    ''
      mkdir -p ${volume}/storage
      cp -f ${serverConfig} ${volume}/server.toml
      chmod 644 ${volume}/server.toml
    '';

  virtualisation.oci-containers.containers.attic-postgres = {
    image = "docker.io/library/postgres:16-alpine";
    ip = "10.88.5.2";
    environment = {
      POSTGRES_USER = "attic";
      POSTGRES_PASSWORD = "attic";
      POSTGRES_DB = "attic";
    };
    volumes = [
      "${volume}/postgresql:/var/lib/postgresql/data"
    ];
    extraOptions = [
      "--health-cmd=pg_isready -U attic"
      "--health-startup-cmd=pg_isready -U attic"
      "--health-startup-interval=100ms"
      "--health-startup-retries=300"
    ];
  };

  systemd.services.podman-attic-postgres.preStart = # sh
    ''
      mkdir -p ${volume}/postgresql
    '';

  # Ensure attic starts after postgres is healthy
  systemd.services.podman-attic = {
    after = [ "podman-attic-postgres.service" ];
    requires = [ "podman-attic-postgres.service" ];
  };

  services.nginx.virtualHosts = {
    "${domain}" = {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          client_max_body_size 10G;
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;
        '';
        proxyPass = address;
      };
    };
  };

}

{ config, ... }:
let
  domain = "photos.tigor.web.id";
  volume = "/var/mnt/wolf/immich";
  version = "release";
  inherit (config.virtualisation.oci-containers.containers.immich-server) ip httpPort;
  address = "http://${ip}:${toString httpPort}";
in
{
  # While Nix provides a service for Immich, a Docker compose setup is preferred because it's easier to backup and manage,
  # especially when dealing with path issues on backing up the media files. Otherwise, a full reupload of media files is required.
  virtualisation.oci-containers.containers.immich-server = {
    image = "ghcr.io/immich-app/immich-server:${version}";
    ip = "10.88.4.1";
    httpPort = 2283;
    autoUpdate.enable = true;
    volumes = [
      "${volume}/server:/usr/src/app/upload"
    ];
    devices = [
      "/dev/dri/renderD128:/dev/dri/renderD128" # For video transcoding.
    ];
    environment = {
      TZ = "Asia/Jakarta";
      NO_COLOR = "true"; # Disable color output in logs.
      # IMMICH_TRUSTED_PROXIES = "0.0.0.0/0";
      REDIS_HOSTNAME = "immich-valkey";
      DB_HOSTNAME = "immich-postgres";
      DB_USERNAME = "immich";
      DB_PASSWORD = "immich";
      DB_DATABASE_NSAME = "immich";
    };
  };
  systemd.services.podman-immich-server.preStart = # sh
    ''
      mkdir -p ${volume}/server/upload
    '';
  virtualisation.oci-containers.containers.immich-machine-learning = {
    image = "ghcr.io/immich-app/immich-machine-learning:${version}";
    volumes = [
      "${volume}/machine-learning:/cache"
    ];
    ip = "10.88.4.2";
    environment = {
      IMMICH_PORT = "3003"; # The port used by the Immich server for machine learning.
    };
    # This server does not have a GPU, so only CPU-based machine learning is used.
  };
  systemd.services.podman-immich-machine-learning.preStart = # sh
    ''
      mkdir -p ${volume}/machine-learning
    '';
  virtualisation.oci-containers.containers.immich-valkey = {
    image = "docker.io/valkey/valkey:8-bookworm";
    podman.sdnotify = "healthy"; # Only notifies 'ready' to systemd when service healthcheck passes.
    ip = "10.88.4.3";
    volumes = [
      "${volume}/valkey:/data"
    ];
    extraOptions = [
      ''--health-cmd=valkey-cli ping | grep PONG''
      ''--health-startup-cmd=valkey-cli ping | grep PONG''
      ''--health-startup-interval=100ms''
      ''--health-startup-retries=300'' # 30 second maximum wait.
    ];
  };
  systemd.services.podman-immich-valkey.preStart = # sh
    ''
      mkdir -p ${volume}/valkey
    '';
  virtualisation.oci-containers.containers.immich-postgres = {
    image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
    ip = "10.88.4.4";
    environment = {
      POSTGRES_USER = "immich";
      POSTGRES_PASSWORD = "immich";
      POSTGRES_DB = "immich";
      POSTGRES_INITDB_ARGS = "--data-checksums";
      DB_STORAGE_TYPE = "HDD";
    };
    volumes = [
      "${volume}/postgresql:/var/lib/postgresql/data"
    ];
    extraOptions = [
      ''--health-cmd=pg_isready -U immich''
      ''--health-startup-cmd=pg_isready -U immich''
      ''--health-startup-interval=100ms''
      ''--health-startup-retries=300'' # 30 second maximum wait.
    ];
  };
  systemd.services.podman-immich-postgres.preStart = # sh
    ''
      mkdir -p ${volume}/postgresql
    '';
  services.nginx.virtualHosts = {
    "${domain}" = {
      forceSSL = true;
      locations."/" = {
        extraConfig = ''
          client_max_body_size 100G;
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
        proxyPass = address;
      };
    };
  };
  # services.homepage-dashboard.groups.Media.services.Immich.settings = {
  #   description = "Family Photos and Videos Server";
  #   href = "https://${domain}";
  #   icon = "immich.svg";
  #   widget = {
  #     type = "immich";
  #     url = "http://immich.lan";
  #     key = "{{HOMEPAGE_VAR_IMMICH_API_KEY}}";
  #     version = 2;
  #   };
  # };
}

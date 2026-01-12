{ config, lib, ... }:
let
  domain = "plane.grandboard.id";
  volume = "/var/mnt/state/grandboard/plane";

  # Container IPs (using 10.88.5.x range)
  ips = {
    web = "10.88.5.1";
    space = "10.88.5.2";
    admin = "10.88.5.3";
    api = "10.88.5.4";
    worker = "10.88.5.5";
    beatworker = "10.88.5.6";
    live = "10.88.5.7";
    db = "10.88.5.10";
    redis = "10.88.5.11";
    mq = "10.88.5.12";
    minio = "10.88.5.13";
  };

  # Common environment for all Plane services
  commonEnv = {
    WEB_URL = "https://${domain}";
    CORS_ALLOWED_ORIGINS = "https://${domain}";
    DEBUG = "0";

    # Database
    PGHOST = ips.db;
    PGDATABASE = "plane";
    POSTGRES_USER = "plane";
    POSTGRES_DB = "plane";
    POSTGRES_PORT = "5432";
    DATABASE_URL = "postgresql://plane:plane@${ips.db}:5432/plane";

    # Redis
    REDIS_HOST = ips.redis;
    REDIS_PORT = "6379";
    REDIS_URL = "redis://${ips.redis}:6379";

    # RabbitMQ
    RABBITMQ_HOST = ips.mq;
    RABBITMQ_PORT = "5672";
    RABBITMQ_DEFAULT_VHOST = "plane";
    AMQP_URL = "amqp://plane:plane@${ips.mq}:5672/plane";

    # MinIO
    USE_MINIO = "1";
    AWS_S3_ENDPOINT_URL = "http://${ips.minio}:9000";
    AWS_S3_BUCKET_NAME = "uploads";
    BUCKET_NAME = "uploads";
    FILE_SIZE_LIMIT = "26214400"; # 25MB
  };

  version = "stable";
in
{
  sops.secrets."grandboard/plane.env" = {
    sopsFile = ./plane.env;
    format = "dotenv";
    key = "";
  };

  # PostgreSQL Database
  virtualisation.oci-containers.containers.plane-db = {
    image = "postgres:15.7-alpine";
    ip = ips.db;
    environment = {
      POSTGRES_USER = "plane";
      POSTGRES_PASSWORD = "plane";
      POSTGRES_DB = "plane";
      PGDATA = "/var/lib/postgresql/data";
    };
    volumes = [
      "${volume}/postgres:/var/lib/postgresql/data"
    ];
    # extraOptions = [
    #   ''--health-cmd=pg_isready -U plane''
    #   ''--health-startup-cmd=pg_isready -U plane''
    #   ''--health-startup-interval=100ms''
    #   ''--health-startup-retries=300''
    # ];
  };
  systemd.services.podman-plane-db.preStart = ''
    mkdir -p ${volume}/postgres
  '';

  # Redis (Valkey)
  virtualisation.oci-containers.containers.plane-redis = {
    image = "valkey/valkey:7.2.5-alpine";
    ip = ips.redis;
    volumes = [
      "${volume}/redis:/data"
    ];
    # extraOptions = [
    #   ''--health-cmd=valkey-cli ping | grep PONG''
    #   ''--health-startup-cmd=valkey-cli ping | grep PONG''
    #   ''--health-startup-interval=100ms''
    #   ''--health-startup-retries=300''
    # ];
  };
  systemd.services.podman-plane-redis.preStart = ''
    mkdir -p ${volume}/redis
  '';

  # RabbitMQ
  virtualisation.oci-containers.containers.plane-mq = {
    image = "rabbitmq:3.13.6-management-alpine";
    ip = ips.mq;
    environment = {
      RABBITMQ_DEFAULT_USER = "plane";
      RABBITMQ_DEFAULT_PASS = "plane";
      RABBITMQ_DEFAULT_VHOST = "plane";
    };
    volumes = [
      "${volume}/rabbitmq:/var/lib/rabbitmq"
    ];
  };
  systemd.services.podman-plane-mq.preStart = ''
    mkdir -p ${volume}/rabbitmq
  '';

  # MinIO Object Storage
  virtualisation.oci-containers.containers.plane-minio = {
    image = "minio/minio:latest";
    ip = ips.minio;
    cmd = [ "server" "/export" "--console-address" ":9090" ];
    environment = {
      MINIO_ROOT_USER = "plane";
      MINIO_ROOT_PASSWORD = "planeminio";
    };
    volumes = [
      "${volume}/minio:/export"
    ];
  };
  systemd.services.podman-plane-minio.preStart = ''
    mkdir -p ${volume}/minio
  '';

  # Migrator Service (runs database migrations)
  virtualisation.oci-containers.containers.plane-migrator = {
    image = "makeplane/plane-backend:${version}";
    ip = "10.88.5.20";
    cmd = [ "./bin/docker-entrypoint-migrator.sh" ];
    environment = commonEnv;
    environmentFiles = [
      config.sops.secrets."grandboard/plane.env".path
    ];
    autoStart = false;
    extraOptions = [ "--restart=no" ];
  };
  systemd.services.podman-plane-migrator = {
    serviceConfig = {
      Restart = lib.mkForce "no";
      RemainAfterExit = true;
    };
  };

  # API Service
  virtualisation.oci-containers.containers.plane-api = {
    image = "makeplane/plane-backend:${version}";
    ip = ips.api;
    httpPort = 8000;
    cmd = [ "./bin/docker-entrypoint-api.sh" ];
    environment = commonEnv // {
      GUNICORN_WORKERS = "2";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/plane.env".path
    ];
    volumes = [
      "${volume}/logs:/code/plane/logs"
    ];
  };
  systemd.services.podman-plane-api.preStart = ''
    mkdir -p ${volume}/logs
  '';
  # systemd.services.podman-plane-api = {
  #   requires = [ "podman-plane-db.service" "podman-plane-redis.service" "podman-plane-mq.service" "podman-plane-minio.service" ];
  #   after = [ "podman-plane-db.service" "podman-plane-redis.service" "podman-plane-mq.service" "podman-plane-minio.service" ];
  # };

  # Worker Service
  virtualisation.oci-containers.containers.plane-worker = {
    image = "makeplane/plane-backend:${version}";
    ip = ips.worker;
    cmd = [ "./bin/docker-entrypoint-worker.sh" ];
    environment = commonEnv;
    environmentFiles = [
      config.sops.secrets."grandboard/plane.env".path
    ];
    volumes = [
      "${volume}/logs:/code/plane/logs"
    ];
  };
  # systemd.services.podman-plane-worker = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Beat Worker Service (Scheduled Tasks)
  virtualisation.oci-containers.containers.plane-beatworker = {
    image = "makeplane/plane-backend:${version}";
    ip = ips.beatworker;
    cmd = [ "./bin/docker-entrypoint-beat.sh" ];
    environment = commonEnv;
    environmentFiles = [
      config.sops.secrets."grandboard/plane.env".path
    ];
    volumes = [
      "${volume}/logs:/code/plane/logs"
    ];
  };
  # systemd.services.podman-plane-beatworker = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Live Service (Real-time)
  virtualisation.oci-containers.containers.plane-live = {
    image = "makeplane/plane-live:${version}";
    ip = ips.live;
    httpPort = 3000;
    environment = commonEnv // {
      API_BASE_URL = "http://${ips.api}:8000";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/plane.env".path
    ];
  };
  # systemd.services.podman-plane-live = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Web Frontend
  virtualisation.oci-containers.containers.plane-web = {
    image = "makeplane/plane-frontend:${version}";
    ip = ips.web;
    httpPort = 3000;
    environment = commonEnv // {
      NEXT_PUBLIC_API_BASE_URL = "";
      NEXT_PUBLIC_ADMIN_BASE_URL = "";
      NEXT_PUBLIC_ADMIN_BASE_PATH = "/god-mode";
      NEXT_PUBLIC_SPACE_BASE_URL = "";
      NEXT_PUBLIC_SPACE_BASE_PATH = "/spaces";
      NEXT_PUBLIC_LIVE_BASE_URL = "";
      NEXT_PUBLIC_LIVE_BASE_PATH = "/live";
    };
  };
  # systemd.services.podman-plane-web = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Space Frontend
  virtualisation.oci-containers.containers.plane-space = {
    image = "makeplane/plane-space:${version}";
    ip = ips.space;
    httpPort = 3000;
    environment = commonEnv;
  };
  # systemd.services.podman-plane-space = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Admin Frontend
  virtualisation.oci-containers.containers.plane-admin = {
    image = "makeplane/plane-admin:${version}";
    ip = ips.admin;
    httpPort = 3000;
    environment = commonEnv;
  };
  # systemd.services.podman-plane-admin = {
  #   requires = [ "podman-plane-api.service" ];
  #   after = [ "podman-plane-api.service" ];
  # };

  # Nginx Configuration
  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "grandboard.id";

    locations."/" = {
      proxyPass = "http://${ips.web}:3000";
      proxyWebsockets = true;
    };

    locations."/api/" = {
      proxyPass = "http://${ips.api}:8000/api/";
      extraConfig = ''
        client_max_body_size 50M;
      '';
    };

    locations."/auth/" = {
      proxyPass = "http://${ips.api}:8000/auth/";
    };

    locations."/spaces/" = {
      proxyPass = "http://${ips.space}:3000/spaces/";
      proxyWebsockets = true;
    };

    locations."/god-mode/" = {
      proxyPass = "http://${ips.admin}:3000/god-mode/";
      proxyWebsockets = true;
    };

    locations."/live/" = {
      proxyPass = "http://${ips.live}:3000/live/";
      proxyWebsockets = true;
    };

    locations."/uploads/" = {
      proxyPass = "http://${ips.minio}:9000/uploads/";
    };
  };

  # MinIO Console (Web UI)
  services.nginx.virtualHosts."minio.grandboard.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.id";
    locations."/" = {
      proxyPass = "http://${ips.minio}:9090";
      proxyWebsockets = true;
    };
  };

}

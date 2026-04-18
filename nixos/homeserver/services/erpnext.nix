{
  config,
  lib,
  pkgs,
  ...
}:
let
  domains = [ "erp.tigor.web.id" ];
  volume = "/var/mnt/state/erpnext";
  version = "v16.14.0";

  # Container IPs (using 10.88.11.x range)
  ips = {
    frontend = "10.88.11.1";
    backend = "10.88.11.2";
    websocket = "10.88.11.3";
    scheduler = "10.88.11.4";
    queueLong = "10.88.11.5";
    queueShort = "10.88.11.6";
    db = "10.88.11.10";
    redisCache = "10.88.11.11";
    redisQueue = "10.88.11.12";
    configurator = "10.88.11.20";
    createSite = "10.88.11.21";
  };

  # Shared volumes for all frappe/erpnext containers
  commonVolumes = [
    "${volume}/sites:/home/frappe/frappe-bench/sites"
    "${volume}/logs:/home/frappe/frappe-bench/logs"
  ];

  # Common environment for frappe app containers
  commonEnv = {
    DB_HOST = ips.db;
    DB_PORT = "3306";
    FRAPPE_REDIS_CACHE = "redis://${ips.redisCache}:6379";
    FRAPPE_REDIS_QUEUE = "redis://${ips.redisQueue}:6379";
  };

  # Script to create/skip each site, then set first domain as default
  createSiteScript =
    lib.concatStringsSep "\n" (
      map (d: ''
        if bench --site ${d} list-apps 2>/dev/null | grep -q erpnext; then
          echo "Site ${d} already exists, skipping"
        else
          echo "Creating site ${d}..."
          bench new-site \
            --mariadb-user-host-login-scope='%' \
            --admin-password="$ADMIN_PASSWORD" \
            --db-root-username=root \
            --db-root-password="$MYSQL_ROOT_PASSWORD" \
            --install-app erpnext \
            ${d}
        fi
      '') domains
    )
    + "\nbench use ${builtins.head domains}";
in
{
  sops.secrets."homeserver/erpnext.env" = {
    sopsFile = ./erpnext.env;
    format = "dotenv";
    key = "";
  };

  # ---------------------------------------------------------------------------
  # MariaDB
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-db = {
    image = "mariadb:11.8";
    ip = ips.db;
    podman.sdnotify = "healthy";
    cmd = [
      "--character-set-server=utf8mb4"
      "--collation-server=utf8mb4_unicode_ci"
      "--skip-character-set-client-handshake"
      "--skip-innodb-read-only-compressed"
    ];
    environment = {
      MARIADB_AUTO_UPGRADE = "1";
    };
    environmentFiles = [ config.sops.secrets."homeserver/erpnext.env".path ];
    volumes = [ "${volume}/mariadb:/var/lib/mysql" ];
    extraOptions = [
      "--health-cmd=healthcheck.sh --connect --innodb_initialized"
      "--health-startup-cmd=healthcheck.sh --connect --innodb_initialized"
      "--health-startup-interval=1s"
      "--health-startup-retries=120"
    ];
  };
  systemd.services.podman-erpnext-db.preStart = ''
    mkdir -p ${volume}/mariadb
  '';

  # ---------------------------------------------------------------------------
  # Redis Cache
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-redis-cache = {
    image = "redis:6.2-alpine";
    ip = ips.redisCache;
    podman.sdnotify = "healthy";
    extraOptions = [
      "--health-cmd=redis-cli ping | grep PONG"
      "--health-startup-cmd=redis-cli ping | grep PONG"
      "--health-startup-interval=100ms"
      "--health-startup-retries=300"
    ];
  };

  # ---------------------------------------------------------------------------
  # Redis Queue
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-redis-queue = {
    image = "redis:6.2-alpine";
    ip = ips.redisQueue;
    podman.sdnotify = "healthy";
    volumes = [ "${volume}/redis-queue:/data" ];
    extraOptions = [
      "--health-cmd=redis-cli ping | grep PONG"
      "--health-startup-cmd=redis-cli ping | grep PONG"
      "--health-startup-interval=100ms"
      "--health-startup-retries=300"
    ];
  };
  systemd.services.podman-erpnext-redis-queue.preStart = ''
    mkdir -p ${volume}/redis-queue
  '';

  # ---------------------------------------------------------------------------
  # Configurator (oneshot – writes common_site_config.json)
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-configurator = {
    image = "frappe/erpnext:${version}";
    ip = ips.configurator;
    entrypoint = "bash";
    cmd = [
      "-c"
      ''
        ls -1 apps > sites/apps.txt;
        bench set-config -g db_host ${ips.db};
        bench set-config -gp db_port 3306;
        bench set-config -g redis_cache "redis://${ips.redisCache}:6379";
        bench set-config -g redis_queue "redis://${ips.redisQueue}:6379";
        bench set-config -g redis_socketio "redis://${ips.redisQueue}:6379";
        bench set-config -gp socketio_port 9000
      ''
    ];
    environment = commonEnv;
    volumes = commonVolumes;
    extraOptions = [ "--restart=no" ];
  };
  systemd.services.podman-erpnext-configurator = {
    after = [
      "podman-erpnext-db.service"
      "podman-erpnext-redis-cache.service"
      "podman-erpnext-redis-queue.service"
    ];
    requires = [
      "podman-erpnext-db.service"
      "podman-erpnext-redis-cache.service"
      "podman-erpnext-redis-queue.service"
    ];
    serviceConfig = {
      RemainAfterExit = true;
      Type = lib.mkForce "oneshot";
    };
    preStart = ''
      mkdir -p ${volume}/sites ${volume}/logs
    '';
  };

  # ---------------------------------------------------------------------------
  # Create Site (oneshot – creates each domain's ERPNext site on first boot)
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-create-site = {
    image = "frappe/erpnext:${version}";
    ip = ips.createSite;
    entrypoint = "bash";
    cmd = [
      "-c"
      createSiteScript
    ];
    environment = commonEnv;
    environmentFiles = [ config.sops.secrets."homeserver/erpnext.env".path ];
    volumes = commonVolumes;
    extraOptions = [ "--restart=no" ];
  };
  systemd.services.podman-erpnext-create-site = {
    after = [ "podman-erpnext-configurator.service" ];
    requires = [ "podman-erpnext-configurator.service" ];
    serviceConfig = {
      RemainAfterExit = true;
      Type = lib.mkForce "oneshot";
    };
  };

  # ---------------------------------------------------------------------------
  # Backend (Gunicorn)
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-backend = {
    image = "frappe/erpnext:${version}";
    ip = ips.backend;
    podman.sdnotify = "healthy";
    environment = commonEnv;
    environmentFiles = [ config.sops.secrets."homeserver/erpnext.env".path ];
    volumes = commonVolumes;
    extraOptions = [
      "--health-cmd=wget --spider -q http://localhost:8000"
      "--health-startup-cmd=wget --spider -q http://localhost:8000"
      "--health-startup-interval=2s"
      "--health-startup-retries=120"
    ];
  };
  systemd.services.podman-erpnext-backend = {
    after = [ "podman-erpnext-create-site.service" ];
    requires = [ "podman-erpnext-create-site.service" ];
  };

  # ---------------------------------------------------------------------------
  # WebSocket (Socket.IO)
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-websocket = {
    image = "frappe/erpnext:${version}";
    ip = ips.websocket;
    cmd = [
      "node"
      "/home/frappe/frappe-bench/apps/frappe/socketio.js"
    ];
    environment = commonEnv;
    volumes = commonVolumes;
  };
  systemd.services.podman-erpnext-websocket = {
    after = [ "podman-erpnext-backend.service" ];
    requires = [ "podman-erpnext-backend.service" ];
  };

  # ---------------------------------------------------------------------------
  # Scheduler
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-scheduler = {
    image = "frappe/erpnext:${version}";
    ip = ips.scheduler;
    cmd = [
      "bench"
      "schedule"
    ];
    environment = commonEnv;
    volumes = commonVolumes;
  };
  systemd.services.podman-erpnext-scheduler = {
    after = [ "podman-erpnext-backend.service" ];
    requires = [ "podman-erpnext-backend.service" ];
  };

  # ---------------------------------------------------------------------------
  # Queue Workers
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-queue-long = {
    image = "frappe/erpnext:${version}";
    ip = ips.queueLong;
    cmd = [
      "bench"
      "worker"
      "--queue"
      "long,default,short"
    ];
    environment = commonEnv;
    volumes = commonVolumes;
  };
  systemd.services.podman-erpnext-queue-long = {
    after = [ "podman-erpnext-backend.service" ];
    requires = [ "podman-erpnext-backend.service" ];
  };

  virtualisation.oci-containers.containers.erpnext-queue-short = {
    image = "frappe/erpnext:${version}";
    ip = ips.queueShort;
    cmd = [
      "bench"
      "worker"
      "--queue"
      "short,default"
    ];
    environment = commonEnv;
    volumes = commonVolumes;
  };
  systemd.services.podman-erpnext-queue-short = {
    after = [ "podman-erpnext-backend.service" ];
    requires = [ "podman-erpnext-backend.service" ];
  };

  # ---------------------------------------------------------------------------
  # Frontend (frappe's built-in nginx, port 8080)
  # Routes to the correct site based on the Host header ($host)
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.erpnext-frontend = {
    image = "frappe/erpnext:${version}";
    ip = ips.frontend;
    podman.sdnotify = "healthy";
    cmd = [ "nginx-entrypoint.sh" ];
    environment = commonEnv // {
      BACKEND = "${ips.backend}:8000";
      # Use nginx $host variable so frappe routes to the correct site per domain
      FRAPPE_SITE_NAME_HEADER = "$host";
      SOCKETIO = "${ips.websocket}:9000";
      # Trust X-Forwarded-For from the podman gateway (host nginx)
      UPSTREAM_REAL_IP_ADDRESS = "10.88.0.1";
      UPSTREAM_REAL_IP_HEADER = "X-Forwarded-For";
      UPSTREAM_REAL_IP_RECURSIVE = "off";
      PROXY_READ_TIMEOUT = "120";
      CLIENT_MAX_BODY_SIZE = "50m";
    };
    volumes = commonVolumes;
    extraOptions = [
      "--health-cmd=wget --spider -q http://localhost:8080"
      "--health-startup-cmd=wget --spider -q http://localhost:8080"
      "--health-startup-interval=2s"
      "--health-startup-retries=60"
    ];
  };
  systemd.services.podman-erpnext-frontend = {
    after = [
      "podman-erpnext-backend.service"
      "podman-erpnext-websocket.service"
    ];
    requires = [
      "podman-erpnext-backend.service"
      "podman-erpnext-websocket.service"
    ];
  };

  # ---------------------------------------------------------------------------
  # Nginx reverse proxy – one vhost per domain, auto-generated from domains list
  # ---------------------------------------------------------------------------
  services.nginx.virtualHosts = lib.genAttrs domains (d: {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ips.frontend}:8080";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 50m;
        proxy_set_header Host $host;
      '';
    };
  });
}

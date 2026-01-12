{ config, ... }:
let
  domain = "huly.grandboard.id";
  volume = "/var/mnt/state/grandboard/huly";
  version = "v0.7.342";

  # Container IPs (using 10.88.5.x range)
  ips = {
    front = "10.88.5.1";
    account = "10.88.5.2";
    transactor = "10.88.5.3";
    collaborator = "10.88.5.4";
    workspace = "10.88.5.5";
    fulltext = "10.88.5.6";
    rekoni = "10.88.5.7";
    stats = "10.88.5.8";
    kvs = "10.88.5.9";
    cockroach = "10.88.5.10";
    elastic = "10.88.5.11";
    minio = "10.88.5.12";
    redpanda = "10.88.5.13";
  };

  # Database URL
  dbUrl = "postgresql://root@${ips.cockroach}:26257/defaultdb?sslmode=disable";

  # Storage config for MinIO
  storageConfig = "minio|${ips.minio}?accessKey=minioadmin&secretKey=minioadmin";

  # Queue config for Redpanda
  queueConfig = "${ips.redpanda}:9092";

  # Common URLs
  urls = {
    account = "http://${ips.account}:3000";
    transactor = "ws://${ips.transactor}:3333";
    collaborator = "http://${ips.collaborator}:3078";
    stats = "http://${ips.stats}:4900";
    rekoni = "http://${ips.rekoni}:4004";
    front = "http://${ips.front}:8080";
  };
in
{
  sops.secrets."grandboard/huly.env" = {
    sopsFile = ./huly.env;
    format = "dotenv";
    key = "";
  };

  # CockroachDB Database
  virtualisation.oci-containers.containers.huly-cockroach = {
    image = "docker.io/cockroachdb/cockroach:v24.2.0";
    ip = ips.cockroach;
    cmd = [
      "start-single-node"
      "--insecure"
      "--accept-sql-without-tls"
    ];
    environment = {
      COCKROACH_DATABASE = "huly";
      COCKROACH_USER = "root";
    };
    volumes = [
      "${volume}/cockroach:/cockroach/cockroach-data"
    ];
  };
  systemd.services.podman-huly-cockroach.preStart = ''
    mkdir -p ${volume}/cockroach
    chown -R 1000:1000 ${volume}/cockroach
  '';

  # Redpanda (Kafka-compatible message broker)
  virtualisation.oci-containers.containers.huly-redpanda = {
    image = "docker.redpanda.com/redpandadata/redpanda:v24.3.6";
    ip = ips.redpanda;
    cmd = [
      "redpanda"
      "start"
      "--kafka-addr"
      "internal://0.0.0.0:9092,external://0.0.0.0:19092"
      "--advertise-kafka-addr"
      "internal://${ips.redpanda}:9092,external://${ips.redpanda}:19092"
      "--pandaproxy-addr"
      "internal://0.0.0.0:8082,external://0.0.0.0:18082"
      "--advertise-pandaproxy-addr"
      "internal://${ips.redpanda}:8082,external://${ips.redpanda}:18082"
      "--schema-registry-addr"
      "internal://0.0.0.0:8081,external://0.0.0.0:18081"
      "--rpc-addr"
      "${ips.redpanda}:33145"
      "--advertise-rpc-addr"
      "${ips.redpanda}:33145"
      "--mode"
      "dev-container"
      "--smp"
      "1"
      "--default-log-level=info"
    ];
    volumes = [
      "${volume}/redpanda:/var/lib/redpanda/data"
    ];
  };
  systemd.services.podman-huly-redpanda.preStart = ''
    mkdir -p ${volume}/redpanda
    chown -R 101:101 ${volume}/redpanda
  '';

  # MinIO Object Storage
  virtualisation.oci-containers.containers.huly-minio = {
    image = "docker.io/minio/minio:latest";
    ip = ips.minio;
    cmd = [
      "server"
      "/data"
      "--address"
      ":9000"
      "--console-address"
      ":9001"
    ];
    environment = {
      MINIO_ROOT_USER = "minioadmin";
      MINIO_ROOT_PASSWORD = "minioadmin";
    };
    volumes = [
      "${volume}/minio:/data"
    ];
  };
  systemd.services.podman-huly-minio.preStart = ''
    mkdir -p ${volume}/minio
  '';

  # Elasticsearch
  virtualisation.oci-containers.containers.huly-elastic = {
    image = "docker.io/elasticsearch:7.14.2";
    ip = ips.elastic;
    environment = {
      ELASTICSEARCH_PORT_NUMBER = "9200";
      BITNAMI_DEBUG = "true";
      "discovery.type" = "single-node";
      ES_JAVA_OPTS = "-Xms1024m -Xmx1024m";
      "http.cors.enabled" = "true";
      "http.cors.allow-origin" = "http://localhost:8082";
    };
    volumes = [
      "${volume}/elastic:/usr/share/elasticsearch/data"
    ];
  };
  systemd.services.podman-huly-elastic.preStart = ''
    mkdir -p ${volume}/elastic
    chown 1000:1000 ${volume}/elastic
  '';

  # Rekoni - Recognition/text extraction service
  virtualisation.oci-containers.containers.huly-rekoni = {
    image = "docker.io/hardcoreeng/rekoni-service:${version}";
    ip = ips.rekoni;
    httpPort = 4004;
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Stats - Metrics service
  virtualisation.oci-containers.containers.huly-stats = {
    image = "docker.io/hardcoreeng/stats:${version}";
    ip = ips.stats;
    httpPort = 4900;
    environment = {
      PORT = "4900";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # KVS - Key-value store
  virtualisation.oci-containers.containers.huly-kvs = {
    image = "docker.io/hardcoreeng/hulykvs:${version}";
    ip = ips.kvs;
    httpPort = 8094;
    environment = {
      HULY_DB_CONNECTION = dbUrl;
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Account - Authentication service
  virtualisation.oci-containers.containers.huly-account = {
    image = "docker.io/hardcoreeng/account:${version}";
    ip = ips.account;
    httpPort = 3000;
    environment = {
      SERVER_PORT = "3000";
      ACCOUNT_PORT = "3000";
      DB_URL = dbUrl;
      TRANSACTOR_URL = "${urls.transactor};wss://${domain}/_transactor";
      STORAGE_CONFIG = storageConfig;
      QUEUE_CONFIG = queueConfig;
      STATS_URL = "https://${domain}/_stats/";
      FRONT_URL = "https://${domain}";
      ACCOUNTS_URL = "https://${domain}/_accounts/";
      MODEL_ENABLED = "*";
      DISABLE_SIGNUP = "true";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Transactor - Core transaction processing
  virtualisation.oci-containers.containers.huly-transactor = {
    image = "docker.io/hardcoreeng/transactor:${version}";
    ip = ips.transactor;
    httpPort = 3333;
    environment = {
      SERVER_PORT = "3333";
      DB_URL = dbUrl;
      STORAGE_CONFIG = storageConfig;
      QUEUE_CONFIG = queueConfig;
      FRONT_URL = "https://${domain}";
      ACCOUNTS_URL = urls.account;
      FULLTEXT_URL = "http://${ips.fulltext}:4700";
      STATS_URL = urls.stats;
      LAST_NAME_FIRST = "true";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Collaborator - Real-time collaboration
  virtualisation.oci-containers.containers.huly-collaborator = {
    image = "docker.io/hardcoreeng/collaborator:${version}";
    ip = ips.collaborator;
    httpPort = 3078;
    environment = {
      COLLABORATOR_PORT = "3078";
      ACCOUNTS_URL = urls.account;
      STATS_URL = urls.stats;
      STORAGE_CONFIG = storageConfig;
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Workspace - Workspace management
  virtualisation.oci-containers.containers.huly-workspace = {
    image = "docker.io/hardcoreeng/workspace:${version}";
    ip = ips.workspace;
    environment = {
      DB_URL = dbUrl;
      ACCOUNTS_DB_URL = dbUrl;
      STORAGE_CONFIG = storageConfig;
      QUEUE_CONFIG = queueConfig;
      TRANSACTOR_URL = "${urls.transactor};wss://${domain}/_transactor";
      ACCOUNTS_URL = urls.account;
      STATS_URL = urls.stats;
      MODEL_ENABLED = "*";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Fulltext - Search indexing
  virtualisation.oci-containers.containers.huly-fulltext = {
    image = "docker.io/hardcoreeng/fulltext:${version}";
    ip = ips.fulltext;
    environment = {
      DB_URL = dbUrl;
      FULLTEXT_DB_URL = "http://${ips.elastic}:9200";
      ELASTIC_INDEX_NAME = "huly_storage_index";
      STORAGE_CONFIG = storageConfig;
      QUEUE_CONFIG = queueConfig;
      ACCOUNTS_URL = urls.account;
      STATS_URL = urls.stats;
      REKONI_URL = urls.rekoni;
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Front - Web UI
  virtualisation.oci-containers.containers.huly-front = {
    image = "docker.io/hardcoreeng/front:${version}";
    ip = ips.front;
    httpPort = 8080;
    environment = {
      SERVER_PORT = "8080";
      ACCOUNTS_URL = "https://${domain}/_accounts/";
      ACCOUNTS_URL_INTERNAL = urls.account;
      REKONI_URL = "https://${domain}/_rekoni/";
      STATS_URL = "https://${domain}/_stats/";
      UPLOAD_URL = "/files/";
      ELASTIC_URL = "http://${ips.elastic}:9200";
      COLLABORATOR_URL = "wss://${domain}/_collaborator/";
      STORAGE_CONFIG = storageConfig;
      TITLE = "Huly";
      DEFAULT_LANGUAGE = "en";
      LAST_NAME_FIRST = "true";
      # Disable optional services
      LOVE_ENDPOINT = "";
      CALENDAR_URL = "";
      GMAIL_URL = "";
      TELEGRAM_URL = "";
      # Disable local email/password login
      DISABLE_SIGNUP = "true";
      HIDE_LOCAL_LOGIN = "true";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/huly.env".path
    ];
  };

  # Nginx Configuration
  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "grandboard.id";

    locations."/" = {
      proxyPass = "http://${ips.front}:8080/";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 256M;
      '';
    };

    locations."/files/" = {
      proxyPass = "http://${ips.minio}:9000/";
      extraConfig = ''
        client_max_body_size 256M;
      '';
    };

    locations."/_ws/" = {
      proxyPass = "http://${ips.transactor}:3333/";
      proxyWebsockets = true;
    };

    locations."/_collaborator/" = {
      proxyPass = "http://${ips.collaborator}:3078/";
      proxyWebsockets = true;
    };

    locations."/_transactor/" = {
      proxyPass = "http://${ips.transactor}:3333/";
      proxyWebsockets = true;
    };

    locations."/_accounts/" = {
      proxyPass = "http://${ips.account}:3000/";
    };

    locations."/_stats/" = {
      proxyPass = "http://${ips.stats}:4900/";
    };

    locations."/_rekoni/" = {
      proxyPass = "http://${ips.rekoni}:4004/";
    };
  };

  # MinIO Console (Web UI) - optional
  services.nginx.virtualHosts."minio.grandboard.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.id";
    locations."/" = {
      proxyPass = "http://${ips.minio}:9001";
      proxyWebsockets = true;
    };
  };
}

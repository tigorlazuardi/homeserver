{
  config,
  pkgs,
  lib,
  ...
}:
let
  domain = "signoz.tigor.web.id";
  otlpDomain = "otlp.tigor.web.id";
  volume = "/var/mnt/state/signoz";
  version = "v0.112.0";
  otelcolVersion = "v0.142.0";
  clickhouseVersion = "25.5.6";
  inherit (config.virtualisation.oci-containers.containers.signoz) ip httpPort;
  collector = {
    inherit (config.virtualisation.oci-containers.containers.signoz-otel-collector) ip httpPort;
  };
  address = "http://${ip}:${toString httpPort}";
  otlpAddress = "http://${collector.ip}:${toString collector.httpPort}";

  # Fetch SigNoz repo for config files
  signozSrc = pkgs.fetchFromGitHub {
    owner = "SigNoz";
    repo = "signoz";
    rev = version;
    hash = "sha256-7+I0k5y1tqh9tB9wdtA5d27C4uj+buXixiSfafHg0xo=";
  };
  clickhouseConfig = "${signozSrc}/deploy/common/clickhouse";

  # Histogram quantile binary for ClickHouse UDF
  histogramQuantile = pkgs.stdenv.mkDerivation {
    pname = "signoz-histogram-quantile";
    version = "0.0.1";
    src = pkgs.fetchurl {
      url = "https://github.com/SigNoz/signoz/releases/download/histogram-quantile%2Fv0.0.1/histogram-quantile_linux_amd64.tar.gz";
      hash = "sha256-M5lwc+ttgre+Tyf5/I7J4oo5Xg8gZ01dVLsvoop1SI0=";
    };
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out/bin
      cp histogram-quantile $out/bin/histogramQuantile
      chmod +x $out/bin/histogramQuantile
    '';
  };

  # Custom cluster.xml with correct container hostnames
  # Based on official SigNoz cluster.xml but with our container names
  clusterXml = pkgs.writeText "cluster.xml" ''
    <?xml version="1.0"?>
    <clickhouse>
        <zookeeper>
            <node index="1">
                <host>signoz-zookeeper</host>
                <port>2181</port>
            </node>
        </zookeeper>
        <remote_servers>
            <cluster>
                <shard>
                    <replica>
                        <host>signoz-clickhouse</host>
                        <port>9000</port>
                    </replica>
                </shard>
            </cluster>
        </remote_servers>
    </clickhouse>
  '';

  # OTEL collector config
  yaml = pkgs.formats.yaml { };
  otelCollectorConfig = yaml.generate "otel-collector-config.yaml" {
    receivers.otlp.protocols = {
      grpc.endpoint = "0.0.0.0:4317";
      http.endpoint = "0.0.0.0:4318";
    };
    processors.batch = {
      send_batch_size = 10000;
      send_batch_max_size = 11000;
      timeout = "10s";
    };
    exporters = {
      clickhousetraces = {
        datasource = "tcp://signoz-clickhouse:9000/signoz_traces";
        low_cardinal_exception_grouping = false;
        use_new_schema = true;
      };
      signozclickhousemetrics = {
        dsn = "tcp://signoz-clickhouse:9000/signoz_metrics";
      };
      clickhouselogsexporter = {
        dsn = "tcp://signoz-clickhouse:9000/signoz_logs";
        timeout = "10s";
        use_new_schema = true;
      };
    };
    service.pipelines = {
      traces = {
        receivers = [ "otlp" ];
        processors = [ "batch" ];
        exporters = [ "clickhousetraces" ];
      };
      metrics = {
        receivers = [ "otlp" ];
        processors = [ "batch" ];
        exporters = [ "signozclickhousemetrics" ];
      };
      logs = {
        receivers = [ "otlp" ];
        processors = [ "batch" ];
        exporters = [ "clickhouselogsexporter" ];
      };
    };
  };
in
{
  # SigNoz - Open Source Observability Platform
  # Retention is configured via UI at Settings -> General
  # Default: 15 days for logs/traces, 30 days for metrics

  virtualisation.oci-containers.containers.signoz-zookeeper = {
    image = "docker.io/signoz/zookeeper:3.7.1";
    ip = "10.88.6.1";
    user = "root";
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/zookeeper:/bitnami/zookeeper"
    ];
    environment = {
      ZOO_SERVER_ID = "1";
      ALLOW_ANONYMOUS_LOGIN = "yes";
      ZOO_AUTOPURGE_INTERVAL = "1";
    };
    extraOptions = [
      "--health-cmd=curl -s -m 2 http://localhost:8080/commands/ruok | grep error | grep null"
      "--health-startup-cmd=curl -s -m 2 http://localhost:8080/commands/ruok | grep error | grep null"
      "--health-startup-interval=1s"
      "--health-startup-retries=60"
    ];
  };
  systemd.services.podman-signoz-zookeeper.preStart = # sh
    ''
      mkdir -p ${volume}/zookeeper
    '';

  virtualisation.oci-containers.containers.signoz-clickhouse = {
    image = "docker.io/clickhouse/clickhouse-server:${clickhouseVersion}";
    ip = "10.88.6.2";
    dependsOn = [ "signoz-zookeeper" ];
    podman.sdnotify = "healthy";
    volumes = [
      "${volume}/clickhouse:/var/lib/clickhouse"
      "${histogramQuantile}/bin/histogramQuantile:/var/lib/clickhouse/user_scripts/histogramQuantile:ro"
      "${clickhouseConfig}/config.xml:/etc/clickhouse-server/config.xml:ro"
      "${clickhouseConfig}/users.xml:/etc/clickhouse-server/users.xml:ro"
      "${clickhouseConfig}/custom-function.xml:/etc/clickhouse-server/custom-function.xml:ro"
      "${clusterXml}:/etc/clickhouse-server/config.d/cluster.xml:ro"
    ];
    environment = {
      CLICKHOUSE_SKIP_USER_SETUP = "1";
    };
    extraOptions = [
      "--health-cmd=wget --spider -q 0.0.0.0:8123/ping"
      "--health-startup-cmd=wget --spider -q 0.0.0.0:8123/ping"
      "--health-startup-interval=1s"
      "--health-startup-retries=60"
      "--ulimit=nproc=65535"
      "--ulimit=nofile=262144:262144"
    ];
  };
  systemd.services.podman-signoz-clickhouse.preStart = # sh
    ''
      mkdir -p ${volume}/clickhouse
    '';

  # Schema migrator - runs once and exits
  virtualisation.oci-containers.containers.signoz-schema-migrator-sync = {
    image = "docker.io/signoz/signoz-schema-migrator:${otelcolVersion}";
    ip = "10.88.6.3";
    dependsOn = [ "signoz-clickhouse" ];
    cmd = [
      "sync"
      "--dsn=tcp://signoz-clickhouse:9000"
      "--up="
    ];
  };
  systemd.services.podman-signoz-schema-migrator-sync = {
    after = [ "podman-signoz-clickhouse.service" ];
    requires = [ "podman-signoz-clickhouse.service" ];
    serviceConfig = {
      Type = lib.mkForce "oneshot";
      RemainAfterExit = true;
      Restart = lib.mkForce "on-failure";
      RestartSec = 5;
    };
  };

  virtualisation.oci-containers.containers.signoz-schema-migrator-async = {
    image = "docker.io/signoz/signoz-schema-migrator:${otelcolVersion}";
    ip = "10.88.6.4";
    dependsOn = [
      "signoz-clickhouse"
      "signoz-schema-migrator-sync"
    ];
    cmd = [
      "async"
      "--dsn=tcp://signoz-clickhouse:9000"
      "--up="
    ];
  };
  systemd.services.podman-signoz-schema-migrator-async = {
    after = [
      "podman-signoz-clickhouse.service"
      "podman-signoz-schema-migrator-sync.service"
    ];
    requires = [
      "podman-signoz-clickhouse.service"
      "podman-signoz-schema-migrator-sync.service"
    ];
    serviceConfig = {
      Type = lib.mkForce "oneshot";
      RemainAfterExit = true;
      Restart = lib.mkForce "on-failure";
      RestartSec = 5;
    };
  };

  virtualisation.oci-containers.containers.signoz = {
    image = "docker.io/signoz/signoz:${version}";
    ip = "10.88.6.5";
    httpPort = 8080;
    podman.sdnotify = "healthy";
    dependsOn = [
      "signoz-clickhouse"
      "signoz-schema-migrator-sync"
      "signoz-schema-migrator-async"
    ];
    volumes = [
      "${volume}/signoz:/var/lib/signoz"
      "${volume}/dashboards:/root/config/dashboards"
    ];
    environment = {
      SIGNOZ_ALERTMANAGER_PROVIDER = "signoz";
      SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN = "tcp://signoz-clickhouse:9000";
      SIGNOZ_SQLSTORE_SQLITE_PATH = "/var/lib/signoz/signoz.db";
      DASHBOARDS_PATH = "/root/config/dashboards";
      STORAGE = "clickhouse";
      GODEBUG = "netdns=go";
      TELEMETRY_ENABLED = "false";
      DEPLOYMENT_TYPE = "docker-standalone-amd";
    };
    extraOptions = [
      "--health-cmd=wget --spider -q localhost:8080/api/v1/health"
      "--health-startup-cmd=wget --spider -q localhost:8080/api/v1/health"
      "--health-startup-interval=1s"
      "--health-startup-retries=120"
    ];
  };
  systemd.services.podman-signoz = {
    after = [
      "podman-signoz-clickhouse.service"
      "podman-signoz-schema-migrator-sync.service"
      "podman-signoz-schema-migrator-async.service"
    ];
    requires = [
      "podman-signoz-clickhouse.service"
      "podman-signoz-schema-migrator-sync.service"
      "podman-signoz-schema-migrator-async.service"
    ];
  };
  systemd.services.podman-signoz.preStart = # sh
    ''
      mkdir -p ${volume}/signoz
      mkdir -p ${volume}/dashboards
    '';

  virtualisation.oci-containers.containers.signoz-otel-collector = {
    image = "docker.io/signoz/signoz-otel-collector:${otelcolVersion}";
    ip = "10.88.6.6";
    dependsOn = [ "signoz" ];
    httpPort = 4318;
    ports = [
      "4317:4317" # OTLP gRPC
      "4318:4318" # OTLP HTTP
    ];
    volumes = [
      "${otelCollectorConfig}:/etc/otel-collector-config.yaml:ro"
    ];
    cmd = [
      "--config=/etc/otel-collector-config.yaml"
    ];
    environment = {
      OTEL_RESOURCE_ATTRIBUTES = "host.name=signoz-host,os.type=linux";
      LOW_CARDINAL_EXCEPTION_GROUPING = "false";
    };
  };
  systemd.services.podman-signoz-otel-collector = {
    after = [
      "podman-signoz.service"
      "podman-signoz-schema-migrator-sync.service"
      "podman-signoz-schema-migrator-async.service"
    ];
    requires = [
      "podman-signoz.service"
      "podman-signoz-schema-migrator-sync.service"
      "podman-signoz-schema-migrator-async.service"
    ];
  };

  # Open OTLP ports for receiving telemetry
  networking.firewall.allowedTCPPorts = [
    4317 # OTLP gRPC
    4318 # OTLP HTTP
  ];

  services.nginx.virtualHosts = {
    "${domain}" = {
      forceSSL = true;
      locations."/" = {
        proxyPass = address;
      };
    };
    "${otlpDomain}" = {
      forceSSL = true;
      locations."/" = {
        proxyPass = otlpAddress;
      };
    };
  };
}

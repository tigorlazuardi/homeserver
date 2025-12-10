{
  config,
  pkgs,
  ...
}:
let
  settings = (pkgs.formats.yaml { }).generate "kouncil.yaml" {
    kouncil = {
      clusters = [
        {
          name = "Bareksa Development";
          brokers = [
            {
              host = "kafka.dev.bareksa.local";
              port = 9093;
            }
            {
              host = "kafka.dev.bareksa.local";
              port = 9094;
            }
            {
              host = "kafka.dev.bareksa.local";
              port = 9095;
            }
          ];
        }
        {
          name = "Bareksa Production";
          brokers = [
            {
              host = "192.168.50.102";
              port = 9092;
            }
            {
              host = "192.168.50.103";
              port = 9092;
            }
            {
              host = "192.168.50.104";
              port = 9092;
            }
          ];
        }
      ];
    };
  };

in
{
  virtualisation.oci-containers.containers.bareksa-kafka-ui = {
    image = "docker.io/consdata/kouncil:latest";
    ip = "10.88.200.2";
    httpPort = 8080;
    volumes = [
      "${settings}:/config/kouncil.yaml"
    ];
    socketActivation = {
      enable = true;
      idleTimeout = "30m";
    };
  };
  services.nginx.virtualHosts."kafka.bareksa.local".locations."/".proxyPass =
    "http://unix:${config.systemd.socketActivations.podman-bareksa-kafka-ui.address}";
  networking.extraHosts = ''
    127.0.0.1 kafka.bareksa.local
    192.168.3.50 kafka.dev.bareksa.local
    192.168.50.102 kafka-host-1 kafka-cluster-jkt-1
    192.168.50.103 kafka-host-2 kafka-cluster-jkt-2
    192.168.50.104 kafka-host-3 kafka-cluster-jkt-3
  '';
}
# let
#   settings = {
#     kafka = {
#       clusters = [
#         {
#           name = "Bareksa Development";
#           bootstrapServers = "kafka.dev.bareksa.local:9093,kafka.dev.bareksa.local:9094,kafka.dev.bareksa.local:9095";
#         }
#         {
#           name = "Bareksa Production";
#           bootstrapServers = "192.168.50.102:9092,192.168.50.103:9092,192.168.50.104:9092";
#           readOnly = true;
#         }
#       ];
#     };
#   };
#   yaml = pkgs.formats.yaml { };
# in
# {
#   sops.templates."bareksa/kafka-ui/config.yaml" = {
#     file = yaml.generate "config.yaml" settings;
#     mode = "0444";
#   };
#   virtualisation.oci-containers.containers.bareksa-kafka-ui = {
#     image = "docker.io/provectuslabs/kafka-ui:latest";
#     ip = "10.88.200.2";
#     httpPort = 8080;
#     volumes = [
#       "${config.sops.templates."bareksa/kafka-ui/config.yaml".path}:/config.yaml"
#     ];
#     socketActivation = {
#       enable = true;
#       idleTimeout = "15m";
#     };
#     environment = {
#       SPRING_CONFIG_ADDITIONAL-LOCATION = "/config.yaml";
#     };
#   };
# }

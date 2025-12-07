{ config, pkgs, ... }:
let
  image = "ghcr.io/grand-board/umbrella/httpserver:main";
  name = "grandboard-umbrella-httpserver";
  inherit (config.virtualisation.oci-containers.containers."${name}") ip httpPort;
  # tinyauth = {
  #   inherit (config.virtualisation.oci-containers.containers."grandboard-tinyauth") ip httpPort;
  # };
in
{
  sops.secrets."grandboard/umbrella/github/tokens/read_registry" = {
    sopsFile = ./umbrella.yaml;
    key = "github/tokens/read_registry";
  };
  sops.secrets."grandboard/umbrella/httpserver.env" = {
    sopsFile = ./httpserver.env;
    key = "";
    format = "dotenv";
  };

  virtualisation.oci-containers.containers."${name}" = {
    inherit image;
    ip = "10.88.21.41";
    httpPort = 3000;
    login = {
      username = "tigorlazuardi";
      registry = "ghcr.io";
      passwordFile = config.sops.secrets."grandboard/umbrella/github/tokens/read_registry".path;
    };
    environment = {
      UMBRELLA_DATABASE_POSTGRES_MAIN_URL = "postgresql://umbrella:umbrella@grandboard-umbrella-postgres:5432/umbrella";
      UMBRELLA_CACHE_VALKEY_MAIN_URL = "redis://grandboard-umbrella-valkey:6379/0";
      UMBRELLA_AUTO_MIGRATE = "true";
      NODE_ENV = "development";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/umbrella/httpserver.env".path
    ];
  };

  services.nginx.virtualHosts."umbrella.grandboard.web.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
    locations."/".proxyPass = "http://${ip}:${toString httpPort}";
  };
  systemd.services."podman-${name}-update" = {
    description = "update umbrella docs container";
    script = ''
      set -e
      ${pkgs.podman}/bin/podman pull ${image}
      systemctl restart podman-${name}.service
    '';
    unitConfig = {
      StartLimitIntervalSec = "30s";
      StartLimitBurst = "3";
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };
  services.webhook.hooks."deploy-${name}" = {
    execute-command = "${pkgs.writeShellScript "deploy-umbrella.docs.sh" "${pkgs.systemd}/bin/systemctl restart podman-${name}-update.service"}";
    response-message = "Umbrella docs deployment triggered";
  };

  systemd.services."podman-${name}" = {
    after = [
      "podman-grandboard-umbrella-postgres.service"
      "podman-grandboard-umbrella-valkey.service"
    ];
    requires = [
      "podman-grandboard-umbrella-postgres.service"
      "podman-grandboard-umbrella-valkey.service"
    ];
  };
}

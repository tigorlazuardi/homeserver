{ config, pkgs, ... }:
let
  name = "grandboard-faraday-cage";
  image = "ghcr.io/grand-board/faraday-cage/webui:main";
  mount = "/var/mnt/state/grandboard/faraday-cage";
  inherit (config.virtualisation.oci-containers.containers.grandboard-faraday-cage) ip httpPort;
  tinyauth = {
    inherit (config.virtualisation.oci-containers.containers."grandboard-tinyauth") ip httpPort;
  };
in
{
  sops.secrets."grandboard/faraday-cage.env" = {
    sopsFile = ./faraday-cage.env;
    format = "dotenv";
    key = "";
  };
  sops.secrets."grandboard/umbrella/github/tokens/read_registry" = {
    sopsFile = ./umbrella/umbrella.yaml;
    key = "github/tokens/read_registry";
  };
  virtualisation.oci-containers.containers."${name}" = {
    inherit image;
    ip = "10.88.22.1";
    httpPort = 3000;
    autoUpdate.enable = true;
    login = {
      username = "tigorlazuardi";
      registry = "ghcr.io";
      passwordFile = config.sops.secrets."grandboard/umbrella/github/tokens/read_registry".path;
    };
    volumes = [
      "${mount}/data:/app/data"
      "${mount}/uploads:/app/uploads"
      "${mount}/artifacts:/app/artifacts"
      "${mount}/app/downloadables:/app/artifacts"
    ];
    environment = {
      NODE_ENV = "production";
      PORT = "3000";
    };
    environmentFiles = [
      config.sops.secrets."grandboard/faraday-cage.env".path
    ];
  };

  systemd.services.podman-grandboard-faraday-cage.preStart = ''
    mkdir -p ${mount}/data
    mkdir -p ${mount}/uploads
  '';

  services.nginx.virtualHosts."faraday.grandboard.web.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
    extraConfig = ''
      auth_request /tinyauth;
      error_page 401 = @tinyauth_login;
    '';
    locations = {
      "/".proxyPass = "http://${ip}:${toString httpPort}";
      "/tinyauth" = {
        proxyPass = "http://${tinyauth.ip}:${toString tinyauth.httpPort}/api/auth/nginx";
        extraConfig =
          # nginx
          ''
            internal;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $http_host;
            proxy_set_header X-Forwarded-Uri $request_uri;
          '';
      };
      "@tinyauth_login".extraConfig = # nginx
        ''
          return 302 https://auth.grandboard.web.id/login?redirect_uri=$scheme://$http_host$request_uri;
        '';
    };
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
    execute-command = "${pkgs.writeShellScript "deploy-faraday-cage.sh" "${pkgs.systemd}/bin/systemctl restart podman-${name}-update.service"}";
    response-message = "Umbrella faraday cage deployment triggered";
  };
}

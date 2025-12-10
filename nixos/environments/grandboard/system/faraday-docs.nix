{ config, pkgs, ... }:
let
  name = "grandboard-faraday-docs";
  image = "ghcr.io/grand-board/faraday-cage/docs:main";
  inherit (config.virtualisation.oci-containers.containers.grandboard-faraday-docs) ip httpPort;
  tinyauth = {
    inherit (config.virtualisation.oci-containers.containers."grandboard-tinyauth") ip httpPort;
  };
in
{
  # docker pull ghcr.io/grand-board/faraday-cage/docs:main-2c4a25f
  sops.secrets."grandboard/umbrella/github/tokens/read_registry" = {
    sopsFile = ./umbrella/umbrella.yaml;
    key = "github/tokens/read_registry";
  };
  virtualisation.oci-containers.containers."${name}" = {
    inherit image;
    ip = "10.88.22.2";
    httpPort = 80;
    autoUpdate.enable = true;
    login = {
      username = "tigorlazuardi";
      registry = "ghcr.io";
      passwordFile = config.sops.secrets."grandboard/umbrella/github/tokens/read_registry".path;
    };
  };
  services.nginx.virtualHosts."faraday-docs.grandboard.web.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
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

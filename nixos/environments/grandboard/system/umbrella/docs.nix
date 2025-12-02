{ config, pkgs, ... }:
let
  image = "ghcr.io/grand-board/umbrella/docs-internal:main";
  name = "grandboard-umbrella-docs-business-internal";
  inherit (config.virtualisation.oci-containers.containers."${name}") ip httpPort;
  tinyauth = {
    inherit (config.virtualisation.oci-containers.containers."grandboard-tinyauth") ip httpPort;
  };
in
{
  sops.secrets."grandboard/umbrella/github/tokens/read_registry" = {
    sopsFile = ./umbrella.yaml;
    key = "github/tokens/read_registry";
  };

  virtualisation.oci-containers.containers."${name}" = {
    inherit image;
    ip = "10.88.21.40";
    httpPort = 3000;
    login = {
      username = "tigorlazuardi";
      registry = "ghcr.io";
      passwordFile = config.sops.secrets."grandboard/umbrella/github/tokens/read_registry".path;
    };
  };

  services.nginx.virtualHosts."internal.grandboard.web.id" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
    extraConfig = ''
      auth_request /tinyauth;
      error_page 401 = @tinyauth_login;
    '';
    locations = {
      "/" = {
        proxyPass = "http://${ip}:${toString httpPort}";
        extraConfig = /* nginx */ ''
          proxy_hide_header Cache-Control; # remove cache headers from upstream
          add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0"; # add no-cache headers so browsers don't cache
        '';
      };
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
    execute-command = "${pkgs.writeShellScript "deploy-umbrella.docs.sh" "${pkgs.systemd}/bin/systemctl restart podman-${name}-update.service"}";
    response-message = "Umbrella docs deployment triggered";
  };
}

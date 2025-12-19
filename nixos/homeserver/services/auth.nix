{ config, lib, ... }:
let
  tinyauth = {
    inherit (config.virtualisation.oci-containers.containers.tinyauth) ip httpPort;
    domain = "auth.tigor.web.id";
    mount = "/var/mnt/state/auth/tinyauth/data";
  };
  pocket-id = {
    inherit (config.virtualisation.oci-containers.containers.pocket-id) ip httpPort;
    domain = "id.tigor.web.id";
    mount = "/var/mnt/state/auth/pocket-id";
  };
  dex = {
    inherit (config.virtualisation.oci-containers.containers.dex) ip httpPort;
    domain = "dex.tigor.web.id";
    mount = "/var/mnt/state/auth/dex";
  };
in
{
  # NGINX Integrations
  options =
    let
      inherit (lib)
        mkOption
        types
        length
        genAttrs
        optionalAttrs
        mkIf
        ;
      inherit (config.virtualisation.oci-containers.containers.tinyauth) environment ip httpPort;
      inherit (environment) APP_URL;
    in
    {
      services.nginx.virtualHosts = mkOption {
        type = types.attrsOf (
          types.submodule (
            { config, ... }:
            {
              options.tinyauth = {
                enable = mkOption {
                  type = types.bool;
                  default = (length config.tinyauth.locations) > 0;
                  description = "enable tinyauth auth proxy. If no specific locations are provided, all endpoints will be protected by tinyauth";
                };
                locations = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "List of locations to protect with Tiny Auth, if empty and tinyauth.enable is true, all locations will be handled with tinyauth";
                };
              };
              config = {
                extraConfig =
                  # This should be made if empty locations but user still enables the tinyauth.
                  # Meaning the user wants all routes.
                  mkIf (config.tinyauth.enable && (length config.tinyauth.locations == 0)) # nginx
                    ''
                      auth_request /tinyauth;
                      error_page 401 = @tinyauth_login;
                    '';
                # Guide: https://tinyauth.app/docs/guides/nginx-proxy-manager.html
                locations =
                  optionalAttrs (config.tinyauth.enable) {
                    "/tinyauth" = {
                      proxyPass = "http://${ip}:${toString httpPort}/api/auth/nginx";
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
                        return 302 ${APP_URL}/login?redirect_uri=$scheme://$http_host$request_uri;
                      '';
                  }
                  // genAttrs config.tinyauth.locations (loc: {
                    extraConfig = # nginx
                      ''
                        auth_request /tinyauth;
                        error_page 401 = @tinyauth_login;
                        auth_request_set $tinyauth_remote_user $upstream_http_remote_user;
                        auth_request_set $tinyauth_remote_groups $upstream_http_remote_groups;
                        auth_request_set $tinyauth_remote_email $upstream_http_remote_email;
                        proxy_set_header Remote-User $tinyauth_remote_user;
                        proxy_set_header Remote-Groups $tinyauth_remote_groups;
                        proxy_set_header Remote-Email $tinyauth_remote_email;
                      '';
                  });
              };
            }
          )
        );
      };
    };
  config = {
    # Tinyauth Service

    sops.secrets."auth/tinyauth.env" = {
      sopsFile = ./tinyauth.env;
      format = "dotenv";
      key = "";
    };
    virtualisation.oci-containers.containers.tinyauth = {
      image = "ghcr.io/steveiliop56/tinyauth:v4";
      ip = "10.88.1.0";
      httpPort = 3000;
      autoUpdate.enable = true;
      environment = {
        APP_TITLE = "Homeserver";
        APP_URL = "https://${tinyauth.domain}";
        OAUTH_AUTO_REDIRECT = "dex";
        SECURE_COOKIES = "true";
        PROVIDERS_DEX_NAME = "dex";
        PROVIDERS_DEX_AUTH_URL = "https://${dex.domain}/auth";
        PROVIDERS_DEX_TOKEN_URL = "https://${dex.domain}/token";
        PROVIDERS_DEX_USER_INFO_URL = "https://${dex.domain}/userinfo";
        PROVIDERS_DEX_SCOPES = "openid,profile,email";
        PROVIDERS_DEX_REDIRECT_URL = "https://${tinyauth.domain}/api/oauth/callback/dex";
        SESSION_EXPIRY = toString (24 * 60 * 60 * 30); # 30 days
      };
      environmentFiles = [
        config.sops.secrets."auth/tinyauth.env".path
      ];
      volumes = [
        "${tinyauth.domain}:/data"
      ];
    };
    systemd.services.podman-tinyauth.preStart = ''
      mkdir -p ${tinyauth.domain}
    '';
    services.nginx.virtualHosts."${tinyauth.domain}" = {
      forceSSL = true;
      locations."/".proxyPass = "http://${tinyauth.ip}:${toString tinyauth.httpPort}";
    };

    # Pocket ID
    virtualisation.oci-containers.containers.pocket-id = {
      image = "ghcr.io/pocket-id/pocket-id:latest";
      ip = "10.88.1.1";
      httpPort = 1411;
      autoUpdate.enable = true;
      environment = {
        APP_URL = "https://${pocket-id.domain}";
        TRUST_PROXY = "true";
      };
      volumes = [
        "${pocket-id.mount}/data:/app/data"
      ];
    };
    systemd.services.podman-pocket-id.preStart = ''
      mkdir -p ${pocket-id.mount}/data
    '';
    services.nginx.virtualHosts."${pocket-id.domain}" = {
      forceSSL = true;
      locations."/".proxyPass = "http://${pocket-id.ip}:${toString pocket-id.httpPort}";
    };

    # Dex OIDC Provider
    sops.secrets."auth/dex.yaml" = {
      sopsFile = ./dex.yaml;
      format = "yaml";
      key = "";
      mode = "0444"; # Container needs read access
    };
    virtualisation.oci-containers.containers.dex = {
      image = "ghcr.io/dexidp/dex:v2.37.0";
      ip = "10.88.1.2";
      httpPort = 5556;
      autoUpdate.enable = true;
      volumes = [
        "${dex.mount}:/var/lib/dex"
        "${config.sops.secrets."auth/dex.yaml".path}:/var/mnt/dex.yaml:ro"
      ];
      cmd = [
        "dex"
        "serve"
        "/var/mnt/dex.yaml"
      ];
    };
    systemd.services.podman-dex.preStart = ''
      mkdir -p ${dex.mount}
      chown 1001:1001 ${dex.mount} # dex runs as uid 1001
    '';
    services.nginx.virtualHosts."${dex.domain}" = {
      forceSSL = true;
      locations."/".proxyPass = "http://${dex.ip}:${toString dex.httpPort}";
    };
  };
}

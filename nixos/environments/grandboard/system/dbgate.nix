{ config, ... }:
let
  domain = "db.grandboard.web.id";
  name = "grandboard-dbgate";
  inherit (config.virtualisation.oci-containers.containers."${name}") ip httpPort;
  tinyauth = {
    inherit (config.virtualisation.oci-containers.containers."grandboard-tinyauth") ip httpPort;
  };
  umbrella = {
    postgres = config.virtualisation.oci-containers.containers."grandboard-umbrella-postgres";
    valkey = config.virtualisation.oci-containers.containers."grandboard-umbrella-valkey";
  };
in
{
  virtualisation.oci-containers.containers."${name}" = {
    image = "dbgate/dbgate:latest";
    ip = "10.88.11.4";
    httpPort = 3000;
    autoUpdate.enable = true;
    volumes = [
      "/var/mnt/state/grandboard/dbgate/data:/root/.dbgate"
    ];
    environment = {
      CONNECTIONS = "umbrella_postgres,umbrella_valkey";

      # Umbrella PostgreSQL
      LABEL_umbrella_postgres = "Umbrella PostgreSQL";
      ENGINE_umbrella_postgres = "postgres@dbgate-plugin-postgres";
      SERVER_umbrella_postgres = umbrella.postgres.ip;
      PORT_umbrella_postgres = "5432";
      USER_umbrella_postgres = "umbrella";
      PASSWORD_umbrella_postgres = "umbrella";
      DATABASE_umbrella_postgres = "umbrella";

      # Umbrella Valkey
      LABEL_umbrella_valkey = "Umbrella Valkey";
      ENGINE_umbrella_valkey = "redis@dbgate-plugin-redis";
      SERVER_umbrella_valkey = umbrella.valkey.ip;
      PORT_umbrella_valkey = "6379";
    };
  };

  systemd.services."podman-${name}" = {
    preStart = ''
      mkdir -p /var/mnt/state/grandboard/dbgate/data
    '';
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "grandboard.web.id";
    extraConfig = ''
      auth_request /tinyauth;
      error_page 401 = @tinyauth_login;
    '';
    locations = {
      "/" = {
        proxyPass = "http://${ip}:${toString httpPort}";
        proxyWebsockets = true;
      };
      "/tinyauth" = {
        proxyPass = "http://${tinyauth.ip}:${toString tinyauth.httpPort}/api/auth/nginx";
        extraConfig = /* nginx */ ''
          internal;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Uri $request_uri;
        '';
      };
      "@tinyauth_login".extraConfig = /* nginx */ ''
        return 302 https://auth.grandboard.web.id/login?redirect_uri=$scheme://$http_host$request_uri;
      '';
    };
  };
}

# LMS (Lightweight Music Server)
# https://github.com/epoupon/lms
{
  config,
  pkgs,
  ...
}:
let
  inherit (config.virtualisation.oci-containers.containers.lms) ip httpPort;
  domain = "lms.tigor.web.id";
  dataDir = "/var/lib/lms";
  musicDir = "/nas/Syncthing/Sync/Music";
  configFile = pkgs.writeText "lms.conf" ''
    # LMS Configuration
    working-dir = "/var/lms";
    listen-port = 5082;
    listen-addr = "0.0.0.0";

    # Behind nginx reverse proxy
    behind-reverse-proxy = true;
    trusted-proxies = ("10.88.0.1");

    # Use tinyauth http headers for authentication
    authentication-backend = "http-headers";
    http-headers-login-field = "Remote-User";

    # Subsonic API
    api-subsonic = true;
  '';
in
{
  virtualisation.oci-containers.containers.lms = {
    image = "epoupon/lms:latest";
    ip = "10.88.1.10";
    httpPort = 5082;
    autoStart = true;
    user = "1000:1000";
    volumes = [
      "${dataDir}:/var/lms"
      "${musicDir}:/music:ro"
      "${configFile}:/etc/lms.conf:ro"
    ];
    environment = {
      TZ = "Asia/Jakarta";
    };
  };

  systemd.services.podman-lms = {
    preStart = ''
      mkdir -p ${dataDir}
      chown 1000:1000 ${dataDir}
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };
}

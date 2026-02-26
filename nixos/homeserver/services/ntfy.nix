# ntfy - Push notification service
# https://ntfy.sh/docs/install/
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.ntfy) ip httpPort;
  domain = "ntfy.tigor.web.id";
  mountDir = "/var/mnt/state/ntfy";
in
{
  sops.secrets."ntfy.env" = {
    sopsFile = ./ntfy.env;
    format = "dotenv";
    key = "";
  };
  virtualisation.oci-containers.containers.ntfy = {
    image = "docker.io/binwiederhier/ntfy:latest";
    ip = "10.88.1.15";
    user = "1000:1000";
    httpPort = 8080;
    autoStart = true;
    cmd = [ "serve" ];
    volumes = [
      "${mountDir}:/var/lib/ntfy"
    ];
    environment = {
      NTFY_BASE_URL = "https://${domain}";
      NTFY_CACHE_FILE = "/var/lib/ntfy/cache.db";
      NTFY_AUTH_FILE = "/var/lib/ntfy/auth.db";
      NTFY_AUTH_DEFAULT_ACCESS = "deny-all";
      NTFY_BEHIND_PROXY = "true";
      NTFY_ATTACHMENT_CACHE_DIR = "/var/lib/ntfy/attachments";
      NTFY_ENABLE_LOGIN = "true";
      NTFY_LISTEN_HTTP = ":${toString httpPort}";
      TZ = "Asia/Jakarta";
    };
    environmentFiles = [
      config.sops.secrets."ntfy.env".path
    ];
  };

  systemd.services.podman-ntfy.preStart = ''
    mkdir -p ${mountDir}
    chown 1000:1000 ${mountDir}
  '';

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      proxyWebsockets = true;
    };
  };
}

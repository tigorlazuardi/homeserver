# Pocket ID - OIDC provider with passkey authentication
# https://github.com/pocket-id/pocket-id
{
  config,
  ...
}:
let
  name = "pocket-id";
  domain = "id.tigor.web.id";
  inherit (config.virtualisation.oci-containers.containers."${name}") ip httpPort;
  dataDir = "/var/lib/pocket-id";
in
{
  virtualisation.oci-containers.containers."${name}" = {
    image = "ghcr.io/pocket-id/pocket-id:latest";
    ip = "10.88.10.10";
    httpPort = 1411;
    environment = {
      PUBLIC_APP_URL = "https://${domain}";
      TRUST_PROXY = "true";
    };
    volumes = [
      "${dataDir}/data:/app/data"
    ];
  };

  systemd.services."podman-${name}".preStart = ''
    mkdir -p ${dataDir}/data
  '';

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    locations."/".proxyPass = "http://${ip}:${toString httpPort}";
  };
}

# FlareSolverr - Proxy server to bypass Cloudflare protection
# https://github.com/FlareSolverr/FlareSolverr
{ config, ... }:
let
  inherit (config.virtualisation.oci-containers.containers.flaresolverr) ip httpPort;
in
{
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    ip = "10.88.1.14";
    httpPort = 8191;
    autoStart = true;
    environment = {
      TZ = "Asia/Jakarta";
      LOG_LEVEL = "info";
    };
  };

  systemd.services.podman-flaresolverr.serviceConfig = {
    Restart = "always";
    RestartSec = "5s";
  };
}

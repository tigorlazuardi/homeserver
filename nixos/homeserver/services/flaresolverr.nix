# FlareSolverr - Proxy server to bypass Cloudflare protection
# https://github.com/FlareSolverr/FlareSolverr
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

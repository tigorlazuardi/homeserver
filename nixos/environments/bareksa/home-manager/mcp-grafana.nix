{
  services.podman.containers.mcp-grafana = {
    autoStart = false; # di jalankan oleh socket activation
    image = "docker.io/mcp/grafana:latest";
    ipv4 = "10.50.1.1";
    autoUpdate = "registry";

  };
}

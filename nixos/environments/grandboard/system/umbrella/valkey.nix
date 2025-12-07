let
  mount = "/var/mnt/state/grandboard/umbrella/valkey";
in
{
  virtualisation.oci-containers.containers."grandboard-umbrella-valkey" = {
    image = "docker.io/valkey/valkey:8-alpine";
    ip = "10.88.21.43";
    # httpPort = 6379;
    volumes = [
      "${mount}:/data"
    ];
  };
  systemd.services.podman-grandboard-umbrella-valkey.preStart = ''
    mkdir -p ${mount}
  '';
}

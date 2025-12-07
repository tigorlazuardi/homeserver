let
  mount = "/var/mnt/state/grandboard/umbrella/postgresql/data";
in
{
  virtualisation.oci-containers.containers."grandboard-umbrella-postgres" = {
    image = "docker.io/postgres:17-alpine";
    ip = "10.88.21.42";
    # httpPort = 5432;
    environment = {
      POSTGRES_USER = "umbrella";
      POSTGRES_PASSWORD = "umbrella";
      POSTGRES_DB = "umbrella";
    };
    volumes = [
      "${mount}:/var/lib/postgresql/data"
    ];
  };

  systemd.services.podman-grandboard-umbrella-postgres.preStart = ''
    mkdir -p ${mount}
  '';
}

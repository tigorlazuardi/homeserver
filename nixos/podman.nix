{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrs'
    filterAttrs
    nameValuePair
    assertMsg
    mkIf
    ;
  cfg = config.virtualisation.oci-containers.containers;
  socketActivatedContainers = filterAttrs (_: c: c.socketActivation.enable) cfg;
in
{
  systemd.timers.podman-auto-update = {
    description = "Timer to auto update podman containers";
    timerConfig = {
      OnCalendar = "daily";
    };
    wantedBy = [ "timers.target" ];
  };
  virtualisation.podman = {
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  networking.firewall.interfaces."podman[0-9]+" = {
    allowedUDPPorts = [ 53 ]; # this needs to be there so that containers can look eachother's names up over DNS
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "pod-ips" ''
      sudo podman inspect --format '{{.Name}} - {{.NetworkSettings.IPAddress}}' $(sudo podman ps -q) | sort -t . -k 3,4
    '')
  ];
  systemd.services = mapAttrs' (
    name: value:
    nameValuePair "podman-${name}-ensure-image" {
      script =
        let
          inherit (pkgs) podman;
        in
        # sh
        ''
          ${pkgs.waitport}/bin/waitport 600 docker.io 443
          set -e
          if ! ${podman}/bin/podman image exists ${value.image}; then
            ${podman}/bin/podman pull ${value.image};
          fi
        '';
      unitConfig = {
        StartLimitIntervalSec = "1h";
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "simple";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 5;
        RestartSteps = 5;
        RestartMaxDelaySec = 30;
      };
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    }
  ) socketActivatedContainers;
}
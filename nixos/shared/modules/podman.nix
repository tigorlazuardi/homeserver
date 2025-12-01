{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.virtualisation.oci-containers.containers =
    let
      inherit (lib)
        mkOption
        types
        mkEnableOption
        mkDefault
        optional
        hasSuffix
        ;
    in
    mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            options = {
              ip = mkOption {
                type = types.nullOr types.str;
                description = "constant IP address for the container, if null the container will have a dynamic ip address assigned by the podman runtime";
                default = null;
              };
              httpPort = mkOption {
                type = types.nullOr types.ints.u16;
                description = ''
                  port that accepts http protocol that will be exposed to nginx.
                  If not null, an nginx entry with [hostname].podman domain without ssl will be created,
                  and a loopback entry to /etc/hosts will be added so it can be accessed from the browser via the domain name.
                '';
                default = null;
              };
              socketActivation = {
                enable = mkEnableOption "socket activation for this container. Requires ip and httpPort to be set, othwerwise an error will be thrown.";
                idleTimeout = mkOption {
                  type = types.str;
                  default = "30s";
                };
              };
              autoUpdate = {
                enable = mkEnableOption "auto update this container's image on a schedule.";
                schedule = mkOption {
                  type = types.str;
                  default = "daily";
                  description = "systemd OnCalendar schedule for auto-updates";
                };
              };
            };
            config = {
              hostname = mkDefault name;
              networks = mkDefault [ "podman" ];
              autoStart = mkDefault (!config.socketActivation.enable);
              extraOptions = optional (config.ip != null) "--ip=${config.ip}";
              autoUpdate.enable = mkDefault (hasSuffix ":latest" config.image);
            };
          }
        )
      );
    };
  config =
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
      autoUpdateContainers = filterAttrs (_: c: c.autoUpdate.enable) cfg;
    in
    lib.mkMerge [
      {
        systemd.socketActivations = mapAttrs' (
          name: value:
          (nameValuePair "podman-${name}" {
            host = mkIf (assertMsg (value.ip != null)
              "virtualisation.oci-containers.containers.${name}.ip must not be null to fulfill the conditions to have socketActivation enabled"
            ) value.ip;
            port = mkIf (assertMsg (value.httpPort != null)
              "virtualisation.oci-containers.containers.${name}.httpPort must not be null to fulfill the conditions to have socketActivation enabled"
            ) value.httpPort;
            idleTimeout = value.socketActivation.idleTimeout;
          })
        ) socketActivatedContainers;
      }
      {
        # Ensure images are pulled for socket activated containers.
        systemd.services = mapAttrs' (
          name: value:
          nameValuePair "podman-${name}-ensure-image" {
            script =
              let
                inherit (pkgs) podman;
              in
              # sh
              ''
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
      {
        systemd.timers = mapAttrs' (
          name: value:
          nameValuePair "podman-${name}-auto-update" {
            description = "Timer to auto update podman container ${name}";
            timerConfig = {
              OnCalendar = value.autoUpdate.schedule;
            };
            wantedBy = [ "timers.target" ];
          }
        ) autoUpdateContainers;
        sysetmd.services = mapAttrs' (
          name: value:
          nameValuePair "podman-${name}-auto-update" {
            script =
              let
                inherit (pkgs) podman;
              in
              # sh
              ''
                set -e
                ${podman}/bin/podman pull ${value.image}
                systemctl restart podman-${name}.service
              '';
            unitConfig = {
              StartLimitIntervalSec = "1h";
              StartLimitBurst = 5;
            };
            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = 5;
              RestartSteps = 5;
              RestartMaxDelaySec = 30;
            };
          }
        ) autoUpdateContainers;
      }
    ];
}

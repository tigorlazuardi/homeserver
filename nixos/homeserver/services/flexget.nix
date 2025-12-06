# FlexGet - Multipurpose automation tool for content like torrents, podcasts, etc.
# https://flexget.com/
{
  config,
  pkgs,
  lib,
  ...
}:
let
  yaml = pkgs.formats.yaml { };
  homeDir = "/var/mnt/state/flexget";
in
{
  options.services.flexget.settings = lib.mkOption {
    type = yaml.type;
    default = { };
  };
  config = lib.mkIf (config.services.flexget.settings != { }) {
    services.flexget = {
      enable = true;
      user = "homeserver";
      config = builtins.readFile (yaml.generate "flexget.yaml" config.services.flexget.settings);
      systemScheduler = false;
      inherit homeDir;
    };

    systemd.services.flexget = {
      serviceConfig.WorkingDirectory = lib.mkForce "/tmp";
      serviceConfig.ExecStartPre = lib.mkBefore [
        "+${pkgs.coreutils}/bin/mkdir -p ${homeDir}"
        "+${pkgs.coreutils}/bin/chown -R 1000:1000 ${homeDir}"
      ];
    };
  };
}

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
      config = yaml.generate "flexget.yaml" config.services.flexget.settings;
    };

    services.nginx.virtualHosts."flexget.tigor.web.id" = {
      forceSSL = true;
      tinyauth.enable = true;
      locations."/".proxyPass = "http://localhost:5050";
    };
  };
}

{ config, lib, ... }:
{
  config = lib.mkIf (config.services.webhook.hooks != { }) {
    sops.secrets."webhook/basic_auth" = {
      sopsFile = ./webhook.yaml;
      owner = "nginx";
      group = "nginx";
      key = "basic_auth";
    };

    # Webhook will be executed as root to allow it to restart services.
    #
    # Do be careful when creating scripts that are triggered by webhooks as they
    # will have full root access to the system.
    services.webhook = {
      enable = (config.services.webhook.hooks != { });
      user = "root";
      group = "root";
    };

    services.nginx.virtualHosts."webhook.tigor.web.id" = {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9000";
        basicAuthFile = config.sops.secrets."webhook/basic_auth".path;
      };
    };
  };
}

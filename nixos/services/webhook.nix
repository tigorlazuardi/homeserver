{
  # Webhook will be executed as root to allow it to restart services.
  #
  # Do be careful when creating scripts that are triggered by webhooks as they
  # will have full root access to the system.
  services.webhook = {
    enable = true;
    user = "root";
    group = "root";
  };
}
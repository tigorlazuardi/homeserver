{ pkgs, ... }:
{
  # SANE scanner support
  hardware.sane = {
    enable = true;
    brscan4.enable = true;
  };

  # Scanner auto-discovery via network
  services.saned.enable = true;

  # User access to scanner
  users.users.tigor.extraGroups = [ "scanner" "lp" ];
}

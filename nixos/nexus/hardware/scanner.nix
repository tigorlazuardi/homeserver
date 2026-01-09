{
  # SANE scanner support
  hardware.sane = {
    enable = true;
    brscan4.enable = true;
    brscan4.netDevices = {
      Tigor = {
        model = "DCP-L2540DW";
        nodename = "BRWBCF4D415C312.local";
      };
    };
  };

  # Scanner auto-discovery via network
  services.saned.enable = true;

  # User access to scanner
  users.users.tigor.extraGroups = [
    "scanner"
    "lp"
  ];
}

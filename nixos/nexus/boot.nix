{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 50;
      };
      efi.canTouchEfiVariables = true;
    };
    tmp.cleanOnBoot = true;
  };
}

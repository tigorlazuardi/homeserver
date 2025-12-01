{ pkgs, ... }:
{
  # AMD GPU (RX 6900 XT)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      amdvlk
      rocmPackages.clr.icd
    ];
    extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];
  };

  # AMDGPU kernel driver
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Hardware video acceleration
  environment.sessionVariables = {
    AMD_VULKAN_ICD = "RADV";
  };
}

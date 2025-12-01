{ pkgs, ... }:
{
  # AMD GPU (RX 6900 XT)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
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

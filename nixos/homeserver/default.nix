{
  imports = [
    ./hardware
    ./programs
    ./services

    ./networking.nix
    ./locale.nix
    ./podman.nix
  ];

  system.stateVersion = "25.11";
}

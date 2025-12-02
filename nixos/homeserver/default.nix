{
  imports = [
    ./hardware
    ./programs
    ./services

    ./locale.nix
    ./networking.nix
    ./podman.nix
    ./sudo.nix
    ./user.nix
  ];

  system.stateVersion = "25.11";
}

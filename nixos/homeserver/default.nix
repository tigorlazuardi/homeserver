{
  imports = [
    ./hardware
    ./programs
    ./services

    ../environments/grandboard/system

    ./locale.nix
    ./networking.nix
    ./podman.nix
    ./sudo.nix
    ./user.nix
  ];

  system.stateVersion = "25.11";
}

{
  imports = [
    ../shared/cli.nix
    ../shared/git.nix

    ./hardware
    ./programs
    ./services

    ./boot.nix
    ./locale.nix
    ./networking.nix
    ./podman.nix
    ./sudo.nix
    ./user.nix
  ];

  system.stateVersion = "25.11";
}

{
  imports = [
    ../shared/cli.nix
    ../shared/git.nix

    ./hardware
    ./programs
    ./services

    ./locale.nix
    ./networking.nix
    ./podman.nix
    ./sudo.nix
    ./user.nix
  ];

  boot.tmp.cleanOnBoot = true;

  system.stateVersion = "25.11";
}

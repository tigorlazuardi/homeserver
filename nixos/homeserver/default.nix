{ inputs, ... }:
{
  imports = [
    ./hardware
    ./programs
    ./services

    ../environments/grandboard/system
    ../environments/howezt/system
    ../environments/planet-melon/system

    ./locale.nix
    ./networking.nix
    ./podman.nix
    ./sudo.nix
    ./user.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.homeserver = import ./home-manager;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "bak";
  };

  system.stateVersion = "25.11";
}

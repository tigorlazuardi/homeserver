{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager

    ../shared/cli.nix
    ../shared/git.nix

    ./desktop/kde

    ./boot.nix
    ./flatpak.nix
    ./hardware
    ./networking.nix
    ./nix-ld.nix
    ./steam.nix
    ./sudo.nix
    ./user.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.tigor = import ./home-manager;
    extraSpecialArgs = { inherit inputs; };
  };

  system.stateVersion = "25.11";
}

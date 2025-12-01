{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager

    ./desktop/kde
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
  };
}

{ inputs, pkgs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.nix-index-database.nixosModules.nix-index

    ../shared/cli.nix
    ../shared/git.nix

    ./desktop/kde

    ./boot.nix
    ./flatpak.nix
    ./hardware
    ./networking.nix
    ./nix-ld.nix
    ./steam.nix
    ./sops.nix
    ./sudo.nix
    ./user.nix

    ../environments/aldhyaksa/system.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.tigor = import ./home-manager;
    extraSpecialArgs = { inherit inputs; };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.nix-index-database.comma.enable = true;

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}

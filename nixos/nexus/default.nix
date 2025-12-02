{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index

    ./desktop/kde

    ./flatpak.nix
    ./hardware
    ./networking.nix
    ./nix-ld.nix
    ./steam.nix
    ./sudo.nix
    ./user.nix

    ../environments/aldhyaksa/system.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.tigor = import ./home-manager;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "bak";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.nix-index-database.comma.enable = true;

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}

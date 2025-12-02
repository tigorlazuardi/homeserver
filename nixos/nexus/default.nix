{ inputs, pkgs, ... }:
{
  imports = [
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

  environment.systemPackages = with pkgs; [
    wl-clipboard
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}

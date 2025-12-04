{ inputs, pkgs, ... }:
{
  imports = [
    ./hardware

    ./flatpak.nix
    ./networking.nix
    ./nix-ld.nix
    ./sudo.nix
    ./user.nix

    ./desktop/kde

    ../environments/aldhyaksa/system.nix
    ../environments/bareksa/system
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

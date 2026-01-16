{ inputs, pkgs, ... }:
{
  imports = [
    ./desktop/kde

    ./faugus.nix
    ./flatpak.nix
    ./hardware
    ./networking.nix
    ./nix-ld.nix
    ./podman.nix
    ./samba-mounts.nix
    ./steam.nix
    ./sudo.nix
    ./user.nix

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

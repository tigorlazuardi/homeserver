{ lib, ... }:
{
  imports = [
    ./modules

    ./boot.nix
    ./cli.nix
    ./direnv.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./nix.nix
    ./sops.nix
    ./fonts.nix
  ];

  time.timeZone = lib.mkDefault "Asia/Jakarta";
}

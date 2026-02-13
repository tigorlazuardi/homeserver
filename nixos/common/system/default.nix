{ lib, ... }:
{
  imports = [
    ./modules

    ./attic-client.nix
    ./boot.nix
    ./cli.nix
    ./direnv.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./nix.nix
    ./sops.nix
    ./scripts.nix
    ./fonts.nix
  ];

  time.timeZone = lib.mkDefault "Asia/Jakarta";
}

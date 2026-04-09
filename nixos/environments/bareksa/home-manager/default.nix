{ pkgs, ... }:
{
  imports = [
    ./flatpak.nix
    ./git.nix
    ./go.nix
  ];
  home.packages = with pkgs; [
    glab
  ];
}

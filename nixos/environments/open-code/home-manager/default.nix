{ inputs, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  home.packages = [
    inputs.opencode.packages.${system}.default
    # inputs.opencode.packages.${system}.desktop
  ];
}

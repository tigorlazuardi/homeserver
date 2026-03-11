{ inputs, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  home.packages = with pkgs; [
    inputs.opencode.packages.${system}.default
    uv # For uvx
    nodejs # for npx
    # inputs.opencode.packages.${system}.desktop
  ];
}

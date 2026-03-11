{ pkgs, ... }:
{
  home.packages = with pkgs; [
    biome
    pnpm
    nodejs
    bun
  ];
}

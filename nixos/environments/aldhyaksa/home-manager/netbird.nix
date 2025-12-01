{ pkgs, ... }:
{
  home.packages = with pkgs; [
    netbird-ui
  ];
}

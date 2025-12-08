{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ faugus-launcher ];
}

{ pkgs, ... }:
{
  programs.vivaldi = {
    enable = true;
    nativeMessagingHosts = [
      pkgs.kdePackages.plasma-browser-integration
    ];
  };
}

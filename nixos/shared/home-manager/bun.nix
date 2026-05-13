{ config, ... }:
{
  programs.bun = {
    enable = true;
    settings = {
      telemetry = false;
    };
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.bun/bin"
  ];
}

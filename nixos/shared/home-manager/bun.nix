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

  programs.fish.interactiveShellInit = /* fish */ ''
    fish_add_path ${config.home.homeDirectory}/.bun/bin
  '';
}

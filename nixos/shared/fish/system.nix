{ pkgs, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
  };
  programs.zoxide = {
    enable = true;
    flags = [
      "--cmd cd"
      "--hook prompt"
    ];
  };
}

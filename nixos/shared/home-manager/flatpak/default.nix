{ inputs, ... }:
{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./bazaar.nix
    ./bruno.nix
    ./firedragon.nix
    ./jellyfin.nix
    ./mpv.nix
    ./obs.nix
    ./slack.nix
    ./spotify.nix
    ./vesktop.nix
    ./vivaldi.nix
    ./whatsapp.nix
    ./zoom.nix
  ];
}

{ nixpkgs, ... }@inputs:
let
  mkNixosConfiguration =
    module:
    nixpkgs.lib.nixosSystem {
      modules = [
        module
        ./common/system
      ];
      specialArgs = { inherit inputs; };
    };
in
{
  homeserver = mkNixosConfiguration ./homeserver;
  nexus = mkNixosConfiguration ./nexus;
  envy = mkNixosConfiguration ./envy;
}

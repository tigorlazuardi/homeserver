{ nixpkgs, ... }@inputs:
let
  mkNixosConfiguration =
    module:
    nixpkgs.lib.nixosSystem {
      modules = [
        module
        ./common/system
        inputs.home-manager.nixosModules.home-manager
        inputs.nix-index-database.nixosModules.nix-index
        {
          programs.nix-index-database.comma.enable = true;
          home-manager.sharedModules = [
            inputs.sops-nix.homeManagerModules.sops
            {
              sops.age.keyFile = "/opt/age-key.txt";
            }
            ./shared/home-manager/nixvim
          ];

        }
      ];
      specialArgs = { inherit inputs; };
    };
in
{
  homeserver = mkNixosConfiguration ./homeserver;
  nexus = mkNixosConfiguration ./nexus;
  envy = mkNixosConfiguration ./envy;
}

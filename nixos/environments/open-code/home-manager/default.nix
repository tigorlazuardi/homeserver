{ config, pkgs, ... }:
{
  sops.secrets =
    let
      opts = {
        sopsFile = ./opencode.yaml;
      };
    in
    {
      "opencode/PLANE_TIGOR_API_KEY" = opts;
      "opencode/VIKUNJA_API_TOKEN" = opts;
    };

  home.packages = with pkgs; [
    (symlinkJoin {
      name = "opencode";
      paths = [
        opencode
        coreutils
        (writeShellScriptBin "opencode" ''
          export PLANE_TIGOR_API_KEY=''$(cat ${config.sops.secrets."opencode/PLANE_TIGOR_API_KEY".path})
          export VIKUNJA_API_TOKEN=''$(cat ${config.sops.secrets."opencode/VIKUNJA_API_TOKEN".path})
          ${opencode}/bin/opencode "$@"
        '')
      ];
    })
    uv # For uvx
    nodejs # for npx
    ripgrep # Fast search (rg)
    fd # Fast find
    git # Version control
    gh # GitHub CLI
    jq # JSON processor
    curl # HTTP client
    wget # File downloader
    tree # Directory listing
    nodejs # For npm/node projects
    python3 # For Python projects
    gnumake # Build tool
    cmake # Build system
    gcc # C/C++ compiler
    nixfmt # Nix formatter
    # inputs.opencode.packages.${system}.desktop
  ];
  xdg.configFile."opencode".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/environments/open-code/home-manager/opencode";
}

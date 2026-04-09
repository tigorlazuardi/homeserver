{
  config,
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs.opencode.packages.${pkgs.system}) opencode;
in
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
    opencode-desktop
    # opencode
    (writeShellScriptBin "opencode" ''
      export PLANE_TIGOR_API_KEY=''$(cat ${config.sops.secrets."opencode/PLANE_TIGOR_API_KEY".path})
      export VIKUNJA_API_TOKEN=''$(cat ${config.sops.secrets."opencode/VIKUNJA_API_TOKEN".path})
      ${opencode}/bin/opencode "$@"
    '')
    (pkgs.writeShellScriptBin "claude-screenshot" ''
      # Create screenshots directory
      SCREENSHOT_DIR="/tmp/claude-screenshots"
      mkdir -p "$SCREENSHOT_DIR"

      # Generate filename with date and time
      FILENAME="$(date +%Y%m%d_%H%M%S).png"
      FILEPATH="$SCREENSHOT_DIR/$FILENAME"

      # Select region with spectacle, opens editor after capture
      ${pkgs.kdePackages.spectacle}/bin/spectacle -n -r -o "$FILEPATH"

      # Check if screenshot was created successfully
      if [ -f "$FILEPATH" ]; then
        # Copy filepath to clipboard
        echo -n "$FILEPATH" | ${pkgs.wl-clipboard}/bin/wl-copy

        # Send notification with preview
        ${pkgs.libnotify}/bin/notify-send \
          --app-name="Claude Screenshot" \
          --icon="$FILEPATH" \
          "Screenshot saved" \
          "$FILEPATH"
      else
        ${pkgs.libnotify}/bin/notify-send \
          --app-name="Claude Screenshot" \
          "Screenshot cancelled" \
          "No screenshot was saved"
      fi
    '')
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

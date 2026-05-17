{
  config,
  pkgs,
  inputs,
  ...
}:
let
  playwrightPkgs = inputs.playwright-web.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages =
    with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
    [
      pi
    ]
    ++ (with pkgs; [
      pnpm
      bun
      nodejs
      zellij # Keep session alive
      ffmpeg
    ])
    ++ (with playwrightPkgs; [
      playwright-test
      playwright-driver
    ]);

  home.file.".pi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/pi-coding-agent/.pi";

  programs.npm = {
    enable = true;
    settings = {
      # Allow for npm install -g stuffs
      prefix = "${config.home.homeDirectory}/.local/npm";
    };
  };

  sops.secrets."pi-coding-agent/secrets.fish" = {
    sopsFile = ./secrets.fish;
    key = "";
    format = "binary";
  };
  programs.fish.enable = true;
  programs.fish.interactiveShellInit = /* fish */ ''
    source ${config.sops.secrets."pi-coding-agent/secrets.fish".path}
    fish_add_path ${config.programs.npm.settings.prefix}/bin
    # Bun binaries
    fish_add_path ${config.home.homeDirectory}/.bun/bin
    # Go binaries
    fish_add_path ${config.home.homeDirectory}/go/bin
  '';

  home.sessionVariables = {
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_BROWSERS_PATH = "${playwrightPkgs.playwright-driver.browsers}";
  };
}

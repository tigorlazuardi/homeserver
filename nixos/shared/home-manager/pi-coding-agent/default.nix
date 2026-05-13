{
  config,
  pkgs,
  inputs,
  ...
}:
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
    ]);

  home.file.".pi".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixos/shared/home-manager/pi-coding-agent/.pi";

  programs.npm = {
    enable = true;
    settings = {
      # Allow for npm install -g stuffs
      prefix = "\${HOME}/.local/npm";
    };
  };
}

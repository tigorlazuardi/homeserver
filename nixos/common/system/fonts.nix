{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    # CJK (Chinese, Japanese, Korean) fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif

    # Developer fonts (Nerd Fonts with icons)
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack
    nerd-fonts.meslo-lg

    # Other popular developer fonts
    fira-code
    jetbrains-mono
    source-code-pro
    cascadia-code
  ];
}

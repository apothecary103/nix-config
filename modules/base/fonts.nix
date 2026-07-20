{ pkgs, ... }:

{
  fonts = {
    packages = with pkgs; [
      # Icon fonts
      material-design-icons
      font-awesome

      # Nerd fonts
      nerd-fonts.symbols-only
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.iosevka

      # Google Noto Fonts
      noto-fonts
      noto-fonts-color-emoji

      # Adobe Source Han Sans/Serif
      source-sans
      source-serif
      source-han-sans
      source-han-serif
      source-han-mono

      # Maple Mono NF CN
      maple-mono.NF-CN-unhinted
    ];
  };
}

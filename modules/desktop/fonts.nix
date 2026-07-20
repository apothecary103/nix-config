let
  fonts = { pkgs, ... }: {
    fonts.packages = with pkgs; [
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

      # Adwaita Sans/Mono — GNOME 48's Inter- and Iosevka-derived UI fonts,
      # tuned for HiDPI panels. The system sans/serif/mono defaults below.
      adwaita-fonts

      # Azuki
      azuki

      # Aporetic
      aporetic
    ];
  };
in
{
  flake.modules.nixos.base = fonts;
  flake.modules.darwin.base = fonts;
}

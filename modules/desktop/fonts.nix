let
  fonts = { pkgs, ... }: {
    fonts.packages = with pkgs; [
      material-design-icons
      font-awesome

      nerd-fonts.symbols-only
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.iosevka

      noto-fonts
      noto-fonts-color-emoji

      source-sans
      source-serif
      source-han-sans
      source-han-serif
      source-han-mono

      maple-mono.NF-CN-unhinted

      # GNOME 48's UI fonts; the sans default in fontconfig.nix.
      adwaita-fonts

      azuki
      aporetic
    ];
  };
in
{
  flake.modules.nixos.base = fonts;
  flake.modules.darwin.base = fonts;
}

let
  # azuki lists thousands of characters it draws nothing for (macron vowels,
  # the middle dot, most symbols). Text then shows holes, since nothing falls
  # back past a glyph the font claims, so these copies claim only what they
  # draw and leave the rest to the next font.
  azuki =
    pkgs:
    pkgs.runCommand "azuki-drawn"
      { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ]; }
      ''
        mkdir -p $out/share/fonts/truetype
        for font in ${pkgs.azuki}/share/fonts/truetype/*.ttf; do
          python3 -I - "$font" "$out/share/fonts/truetype/$(basename "$font")" <<'PY'
        import sys
        from fontTools.pens.boundsPen import BoundsPen
        from fontTools.ttLib import TTFont

        font = TTFont(sys.argv[1])
        glyphs = font.getGlyphSet()

        def empty(name):
            pen = BoundsPen(glyphs)
            glyphs[name].draw(pen)
            return pen.bounds is None

        blank = {name for name in font.getGlyphOrder() if empty(name)}
        for table in font["cmap"].tables:
            table.cmap = {
                code: name
                for code, name in table.cmap.items()
                if name not in blank or chr(code).isspace()
            }
        font.save(sys.argv[2])
        PY
        done
      '';

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

      (azuki pkgs)
      aporetic
    ];
  };
in
{
  flake.modules.nixos.base = fonts;
  flake.modules.darwin.base = fonts;
}

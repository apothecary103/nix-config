{
  flake.modules.nixos.base = {
    fonts.fontconfig = {
      enable = true;
      antialias = true;

      # Retina-panel rendering, matching macOS: no hinting, grayscale AA.
      # Subpixel/LCD filtering is wrong at 2x — it only helps low-DPI panels.
      hinting = {
        enable = false;
        autohint = false;
        style = "none";
      };

      subpixel = {
        rgba = "none";
        lcdfilter = "none";
      };

      # Without this, apps asking for a generic family get whatever fontconfig
      # guesses (often a thin fallback). Pin one coherent set. sansSerif/serif
      # are deliberately the Source (OTF/CFF) families: those are the ONLY fonts
      # here that FreeType stem-darkening can fatten (see note below), so they
      # land closest to macOS weight for free.
      defaultFonts = {
        monospace = [ "Maple Mono NF CN" ];
        sansSerif = [
          "Source Sans 3"
          "Noto Sans"
        ];
        serif = [
          "Source Serif 4"
          "Noto Serif"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };

    # macOS-like stem darkening. IMPORTANT: FreeType only darkens CFF/Type1/CID
    # (i.e. OTF) fonts — the TrueType engine has no stem-darkening code at all.
    # So this fattens Source Sans/Serif/Han (OTF) but does NOTHING for Maple
    # Mono, the Nerd Fonts, or Noto (all TrueType); those rely on weight instead.
    # darkening-parameters is bumped above the defaults for a heavier look.
    environment.sessionVariables = {
      FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 cff:darkening-parameters=500,400,1000,300,1500,200,2000,100 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
    };
  };
}

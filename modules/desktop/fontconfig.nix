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
      # guesses (often a thin fallback). Pin one coherent, macOS-adjacent set.
      #
      # sansSerif is Adwaita Sans — GNOME 48's default UI face, a customised
      # Inter tuned for HiDPI. Inter is the closest freely-available stand-in
      # for macOS's San Francisco, so this is the "GNOME typography" the whole
      # desktop chrome (GTK, mako, fuzzel, ...) now shares. Noto/Source Han fill
      # the Unicode and CJK gaps. serif stays on the Source (OTF) families,
      # which stem-darkening can still fatten (see note below).
      #
      # monospace stays Maple Mono NF CN — a deliberate coding/terminal choice,
      # not part of the "horrible" UI stack this replaces.
      defaultFonts = {
        monospace = ["Maple Mono NF CN"];
        sansSerif = [
          "Adwaita Sans"
          "Noto Sans"
          "Source Han Sans"
        ];
        serif = [
          "Source Serif 4"
          "Noto Serif"
        ];
        emoji = ["Noto Color Emoji"];
      };

      # macOS applies a light "font smoothing" that fattens text; FreeType's
      # stem-darkening only does the same for OTF/CFF fonts, so on a
      # hinting-off Retina panel the Regular cut of Adwaita Sans (a TrueType
      # variable font) renders noticeably thinner than San Francisco does.
      # Adwaita Sans is variable Thin..Black, so instead of synthetic
      # emboldening we simply promote its default weight one step, Regular ->
      # Medium, wherever the family is requested by name or as generic sans.
      # This is the single source of truth for chrome weight — app font
      # strings can stay plain "Adwaita Sans" and still come out Medium.
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <match target="pattern">
            <test name="family"><string>Adwaita Sans</string></test>
            <test name="weight" compare="eq"><const>regular</const></test>
            <edit name="weight" mode="assign"><const>medium</const></edit>
          </match>
        </fontconfig>
      '';
    };

    # macOS-like stem darkening. IMPORTANT: FreeType only darkens CFF/Type1/CID
    # (i.e. OTF) fonts — the TrueType engine has no stem-darkening code at all.
    # So this fattens Source Serif/Han (OTF) but does NOTHING for Adwaita Sans,
    # Maple Mono, the Nerd Fonts, or Noto (all TrueType); those rely on their
    # own weight/design (Adwaita Sans is already tuned for HiDPI) instead.
    # darkening-parameters is bumped above the defaults for a heavier look.
    environment.sessionVariables = {
      FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 cff:darkening-parameters=500,400,1000,300,1500,200,2000,100 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
    };
  };
}

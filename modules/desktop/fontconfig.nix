let
  # Retina-panel rendering, matching macOS: no hinting, grayscale AA.
  # Subpixel/LCD filtering is wrong at 2x — it only helps low-DPI panels.
  fontconfig = {
    enable = true;
    antialias = true;

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
    # desktop chrome (GTK, quickshell, ...) now shares. Noto/Source Han fill
    # the Unicode and CJK gaps. serif stays on the Source (OTF) families,
    # which stem-darkening can still fatten (see note below).
    #
    # monospace stays Maple Mono NF CN — a deliberate coding/terminal choice,
    # not part of the "horrible" UI stack this replaces.
    defaultFonts = {
      monospace = [ "Maple Mono NF CN" ];
      sansSerif = [
        "Adwaita Sans"
        "Noto Sans"
        "Source Han Sans"
      ];
      serif = [
        "Source Serif 4"
        "Noto Serif"
      ];
      emoji = [ "Noto Color Emoji" ];
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
    # Web typography: pages overwhelmingly ask for the macOS/Windows stacks
    # (Helvetica Neue, Helvetica, Arial, Roboto, Segoe UI). Left alone,
    # fontconfig hands Helvetica to TeX Gyre Heros and Arial to Liberation
    # Sans — print-era clones that look nothing like what those pages get on
    # macOS — and the families that *do* fall through to Adwaita Sans arrive
    # under their original pattern name, so the Regular→Medium promotion
    # below never fires and web body text renders a weight thinner than the
    # desktop chrome. Rewrite them all to the one UI face, the same move
    # macOS makes when it resolves that stack to San Francisco. These
    # substitutions run first, so the rewritten patterns then hit the weight
    # rule and come out Medium like everything else.
    localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        ${builtins.concatStringsSep "\n  " (
          map
            (family: ''
              <match target="pattern">
                  <test name="family"><string>${family}</string></test>
                  <edit name="family" mode="assign" binding="same"><string>Adwaita Sans</string></edit>
                </match>'')
            [
              "Helvetica"
              "Helvetica Neue"
              "Arial"
              "Roboto"
              "Segoe UI"
            ]
        )}
        <match target="pattern">
          <test name="family"><string>Times New Roman</string></test>
          <edit name="family" mode="assign" binding="same"><string>Source Serif 4</string></edit>
        </match>
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
  freetypeProperties = "cff:no-stem-darkening=0 cff:darkening-parameters=500,400,1000,300,1500,200,2000,100 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
in
{
  flake.modules.nixos.base = {
    fonts.fontconfig = fontconfig;
    environment.sessionVariables.FREETYPE_PROPERTIES = freetypeProperties;
  };
}

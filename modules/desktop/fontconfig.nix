{ lib, ... }:
let
  # Web and print families that no font here actually provides, mapped onto the
  # faces that should answer for them. Without this fontconfig hands Helvetica
  # to TeX Gyre Heros and Arial to Liberation Sans — print-era clones.
  substitutions = {
    "Helvetica" = "Adwaita Sans";
    "Helvetica Neue" = "Adwaita Sans";
    "Arial" = "Adwaita Sans";
    "Roboto" = "Adwaita Sans";
    "Segoe UI" = "Adwaita Sans";
    "Times New Roman" = "Source Serif 4";
  };

  # The autofitter's darkening distorts icon glyphs (FreeType #1334), so the
  # TrueType icon fonts skip hinting and with it the autofitter. Font Awesome
  # is CFF, which the Adobe engine darkens like any other outline.
  iconFamilies = [
    "Material Design Icons"
    "Symbols Nerd Font"
    "Symbols Nerd Font Mono"
  ];

  unhinted = family: ''
    <match target="font">
      <test name="family"><string>${family}</string></test>
      <edit name="hinting" mode="assign"><bool>false</bool></edit>
    </match>'';

  substituteFamily = from: to: ''
    <match target="pattern">
      <test name="family"><string>${from}</string></test>
      <edit name="family" mode="assign" binding="same"><string>${to}</string></edit>
    </match>'';

  # Retina-panel rendering, matching macOS: grayscale AA, no subpixel/LCD
  # filtering (wrong at 2x, it only helps low-DPI panels).
  #
  # hintslight is not here for hinting: the autofitter, the one TrueType path
  # with stem darkening, only darkens in FreeType's light mode, and that mode
  # sends every TrueType font (Adwaita Sans, Maple Mono, Noto, the Nerd Fonts)
  # through it. The cost is snapping heights to the pixel grid, under half a
  # device pixel at 2x. autohint stays off so CFF fonts keep the Adobe engine,
  # which darkens in any mode.
  fontconfig = {
    enable = true;
    antialias = true;

    hinting = {
      enable = true;
      autohint = false;
      style = "slight";
    };

    subpixel = {
      rgba = "none";
      lcdfilter = "none";
    };

    # Without this, apps asking for a generic family get whatever fontconfig
    # guesses, often a thin fallback. Adwaita Sans is GNOME 48's UI face, an
    # Inter tuned for HiDPI and the closest free stand-in for San Francisco.
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

    localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList substituteFamily substitutions)}
      ${lib.concatMapStringsSep "\n" unhinted iconFamilies}
      </fontconfig>
    '';
  };

  # CoreText's font smoothing, measured on this Mac (macOS 27, smoothing on vs
  # off; SF, Helvetica and Menlo alike): every stem gains min(0.6, 0.0116 *
  # ppem) device px while advances stay put, so 13 pt UI text at 2x (26 ppem)
  # gains 0.3 px. FreeType's darkening also leaves advances alone.
  #
  # The Adobe engine (CFF, Type 1, CID) adds y/1000 px at every size; 300 is
  # CoreText at UI sizes. Each of those drivers keeps its own curve.
  psDarkening = "500,300,1000,300,1500,300,2000,300";

  # The autofitter, which darkens every TrueType font, turns its amount into
  # pixels and then applies that number to the outline in font units, so the
  # gain is round(0.064 * y) * ppem / upem px: proportional to size like
  # CoreText's, but scaled by the font's upem. Since the variable is global
  # only one upem can be exact; this curve is for 2048 (Adwaita Sans and most
  # web fonts), where 371 gives 0.0116 * ppem and the taper over stem width
  # (x, in 1/1000 px) holds CoreText's 0.6 px cap. 1000-upem fonts such as
  # Noto come out twice as dark; Ghostty sets its own curve for Maple Mono.
  freetypeProperties =
    autofitDarkening:
    lib.concatStringsSep " " (
      [
        "autofitter:no-stem-darkening=0"
        "autofitter:darkening-parameters=${autofitDarkening}"
      ]
      ++ lib.concatMap (driver: [
        "${driver}:no-stem-darkening=0"
        "${driver}:darkening-parameters=${psDarkening}"
      ]) [ "cff" "type1" "t1cid" ]
    );
in
{
  _module.args.freetypeProperties = freetypeProperties;

  flake.modules.nixos.base = {
    fonts.fontconfig = fontconfig;
    environment.sessionVariables.FREETYPE_PROPERTIES =
      freetypeProperties "500,371,4850,371,5970,300,9330,192";
  };
}

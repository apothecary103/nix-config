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

  substituteFamily = from: to: ''
    <match target="pattern">
      <test name="family"><string>${from}</string></test>
      <edit name="family" mode="assign" binding="same"><string>${to}</string></edit>
    </match>'';

  # Retina-panel rendering, matching macOS: grayscale AA, no subpixel/LCD
  # filtering (wrong at 2x, it only helps low-DPI panels).
  #
  # hintslight is not here for hinting: FreeType only darkens stems in its
  # light render mode, and that mode sends TrueType fonts (Adwaita Sans, Maple
  # Mono, Noto, the Nerd Fonts) through the autofitter, the one TrueType path
  # with stem darkening. The cost is snapping heights to the pixel grid, under
  # half a device pixel at 2x. autohint stays off so CFF fonts keep the Adobe
  # engine, which darkens on its own.
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
      </fontconfig>
    '';
  };

  # CoreText's "font smoothing" dilates every outline by min(0.3 px, 0.0121 *
  # ppem) per side (Pathfinder's measurements), so at 2x every stem from 12.4 px
  # text up gains a flat 0.6 device px while advances stay put. FreeType's
  # darkening also leaves advances alone; 500 (0.5 px across the stem) is the
  # most it accepts, held flat over every stem width as CoreText does. The
  # default curves fall to nothing at a Retina 13 px stem, which is why text
  # looked thin. One curve serves all engines: cff, type1 and t1cid share it.
  darkening = "500,500,1000,500,1500,500,2000,500";
  freetypeProperties = lib.concatStringsSep " " [
    "autofitter:no-stem-darkening=0"
    "autofitter:darkening-parameters=${darkening}"
    "cff:no-stem-darkening=0"
    "cff:darkening-parameters=${darkening}"
    "type1:no-stem-darkening=0"
    "t1cid:no-stem-darkening=0"
  ];
in
{
  flake.modules.nixos.base = {
    fonts.fontconfig = fontconfig;
    environment.sessionVariables.FREETYPE_PROPERTIES = freetypeProperties;
  };
}

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

  # Stem-darkening only fattens OTF/CFF (see freetypeProperties below), so on a
  # hinting-off Retina panel the Regular cut of Adwaita Sans (TrueType) renders
  # thinner than San Francisco. It is variable Thin..Black, so rather than
  # synthetic emboldening this promotes Regular -> Medium wherever the family is
  # asked for. Single source of truth for chrome weight: app font strings can
  # stay plain "Adwaita Sans" and still come out Medium.
  #
  # It is emitted after the substitutions so patterns rewritten to Adwaita Sans
  # hit it too. In the other order they would keep their original pattern name,
  # the promotion would never fire, and web body text would render lighter than
  # the desktop chrome.
  promoteAdwaitaSansToMedium = ''
    <match target="pattern">
      <test name="family"><string>Adwaita Sans</string></test>
      <test name="weight" compare="eq"><const>regular</const></test>
      <edit name="weight" mode="assign"><const>medium</const></edit>
    </match>'';

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
    # guesses, often a thin fallback. Adwaita Sans is GNOME 48's UI face, an
    # Inter tuned for HiDPI and the closest free stand-in for San Francisco.
    # serif stays on the Source (OTF) families, which stem-darkening can fatten
    # (see below).
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
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList substituteFamily substitutions ++ [ promoteAdwaitaSansToMedium ]
      )}
      </fontconfig>
    '';
  };

  # macOS-like stem darkening, bumped above FreeType's defaults. Only applies
  # to CFF/Type1/CID (OTF) fonts — the TrueType engine has no stem-darkening
  # code at all — so this fattens Source Serif/Han but does nothing for Adwaita
  # Sans, Maple Mono, the Nerd Fonts or Noto.
  freetypeProperties = "cff:no-stem-darkening=0 cff:darkening-parameters=500,400,1000,300,1500,200,2000,100 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
in
{
  flake.modules.nixos.base = {
    fonts.fontconfig = fontconfig;
    environment.sessionVariables.FREETYPE_PROPERTIES = freetypeProperties;
  };
}

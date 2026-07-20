{config, ...}: {
  fonts.fontconfig = {
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
  };

  # Enable macOS-like stem darkening for FreeType globally
  environment.sessionVariables = {
    FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
  };
}

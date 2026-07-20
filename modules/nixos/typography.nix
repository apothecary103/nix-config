{ config, ... }:
{
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
}

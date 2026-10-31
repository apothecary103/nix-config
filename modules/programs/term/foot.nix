{
  # The river rice's foot in Maple Mono, padded 18 px with the slack centred, a beam
  # cursor, in Catppuccin Macchiato at 93 % like ghostty.
  flake.modules.hjem.linux.orchard.foot = {
    theme = "catppuccin";
    flavor = "macchiato";
  };

  flake.modules.hjem.linux.rum.programs.foot = {
    enable = true;

    settings = {
      main = {
        font = "Maple Mono NF CN:size=13";
        pad = "18x18 center";
        resize-delay-ms = 0;
      };

      colors.alpha = 0.93;
      cursor.style = "beam";
      bell.urgent = "yes";
      csd.preferred = "server";

      scrollback.lines = 10000;
    };
  };
}

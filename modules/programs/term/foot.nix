{
  # The river rice's foot: azuki, padded 18 px with the slack centred, a beam
  # cursor, opaque.
  flake.modules.hjem.linux.rum.programs.foot = {
    enable = true;

    settings = {
      main = {
        font = "azuki_font:size=14";
        pad = "18x18 center";
        resize-delay-ms = 0;
      };

      cursor.style = "beam";
      bell.urgent = "yes";
      csd.preferred = "server";

      scrollback.lines = 10000;
    };
  };
}

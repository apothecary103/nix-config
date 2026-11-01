{
  # The launcher after the quickshell launcher on main (quickshell/qml/launcher),
  # to sit with the bar and the overlay: Maple Mono at medium weight on
  # Catppuccin's base, rounded as the bar's theme is (7), a magnifier for the
  # prompt and a `search...` placeholder, the chosen row inverted, matches in
  # the accent the wallpaper suggests (theme.nix), kept current as the
  # wallpaper changes through an included file. A touch clear for river's
  # blur, which takes the `launcher` namespace (river/package.nix).
  flake.modules.hjem.linux =
    {
      lib,
      palette,
      accent,
      ...
    }:
    let
      c = palette.native;
      opaque = colour: "${lib.removePrefix "#" colour}ff";
      magnifier = builtins.fromJSON ''"\uf002"''; # Font Awesome's magnifier
      live = "${accent.state}/fuzzel.ini";
    in
    {
      # Read each time fuzzel starts, so nothing needs telling.
      accent.live.fuzzel = {
        path = live;
        template = ''
          [colors]
          match=@accent@ff
        '';
      };

      rum.programs.fuzzel = {
        enable = true;

        settings = {
          main = {
            include = live;
            font = "Maple Mono NF CN:size=13:weight=medium";
            prompt = ''"${magnifier}  "'';
            placeholder = "search...";
            terminal = "ghostty -e";
            # Rows of 26 pt, between fuzzel's tight default and the quickshell
            # launcher's 42 px (fuzzel's px are the buffer's, so points it is),
            # with room to breathe around the list.
            lines = 8;
            line-height = 26;
            width = 40;
            tabs = 4;
            horizontal-pad = 34;
            vertical-pad = 28;
            inner-pad = 16;
          };

          colors = {
            background = "${lib.removePrefix "#" c.base}f2";
            text = opaque c.text;
            prompt = opaque c.subtext1;
            placeholder = opaque c.surface2;
            input = opaque c.text;
            selection = opaque c.text;
            selection-text = opaque c.base;
            selection-match = opaque c.base;
            counter = opaque c.overlay0;
            border = opaque c.base;
          };

          border = {
            radius = 7;
            width = 0;
          };
        };
      };
    };
}

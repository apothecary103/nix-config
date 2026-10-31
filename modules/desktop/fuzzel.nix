{
  # The launcher after the quickshell launcher on main (quickshell/qml/launcher),
  # to sit with the bar and the overlay: Maple Mono at medium weight on
  # Catppuccin's base, rounded as the bar's theme is (7), a magnifier for the
  # prompt and a `search...` placeholder, the chosen row inverted, matches in
  # the accent the wallpaper suggests (theme.nix). A touch clear for river's
  # blur, which takes the `launcher` namespace (river/package.nix).
  flake.modules.hjem.linux =
    { lib, palette, ... }:
    let
      c = palette.native;
      opaque = colour: "${lib.removePrefix "#" colour}ff";
      magnifier = builtins.fromJSON ''"\uf002"''; # Font Awesome's magnifier
    in
    {
      rum.programs.fuzzel = {
        enable = true;

        settings = {
          main = {
            font = "Maple Mono NF CN:size=12:weight=medium";
            prompt = ''"${magnifier}  "'';
            placeholder = "search...";
            terminal = "ghostty -e";
            lines = 8;
            width = 34;
            tabs = 4;
            horizontal-pad = 25;
            vertical-pad = 25;
            inner-pad = 10;
          };

          colors = {
            background = "${lib.removePrefix "#" c.base}f2";
            text = opaque c.text;
            prompt = opaque c.subtext1;
            placeholder = opaque c.surface2;
            input = opaque c.text;
            match = opaque palette.ui.accent;
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

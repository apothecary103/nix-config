{
  # The launcher as the river rice has it, in Maple Mono: a ＃ prompt, roomy
  # padding. Orchard colours it; the background drops to 72 % so river's blur
  # shows through, with a hairline edge and corners like the shell's panels.
  flake.modules.hjem.linux =
    { lib, palette, ... }:
    let
      bare = lib.removePrefix "#";
    in
    {
      rum.programs.fuzzel = {
        enable = true;

        settings = {
          main = {
            font = "Maple Mono NF CN:size=13";
            prompt = ''"＃ "'';
            terminal = "ghostty -e";
            lines = 12;
            width = 32;
            tabs = 4;
            horizontal-pad = 24;
            vertical-pad = 18;
            inner-pad = 12;
          };

          colors = {
            background = "${bare palette.surface.background}b8";
            border = "${bare palette.surface.text}1f";
          };

          border = {
            radius = 18;
            width = 1;
          };
        };
      };
    };
}

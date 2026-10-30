{
  # The launcher as the river rice has it: azuki, a ＃ prompt, square corners,
  # roomy padding. Orchard colours it.
  flake.modules.hjem.linux.rum.programs.fuzzel = {
    enable = true;

    settings = {
      main = {
        font = "azuki_font:size=14";
        prompt = ''"＃ "'';
        terminal = "ghostty -e";
        lines = 12;
        width = 32;
        tabs = 4;
        horizontal-pad = 24;
        vertical-pad = 18;
        inner-pad = 12;
      };

      border.radius = 0;
    };
  };
}

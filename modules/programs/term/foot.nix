{
  flake.modules.homeManager.linux.programs.foot = {
    enable = true;

    settings = {
      main = {
        font = "Maple Mono NF CN:weight=medium:size=12";
        pad = "20x10";
      };

      colors-dark.alpha = 0.93;
      csd.preferred = "server";

      scrollback.lines = 10000;
    };
  };
}

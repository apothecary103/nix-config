{
  flake.modules.homeManager.base =
    { lib, pkgs, ... }:
    {
      programs.foot = lib.mkIf pkgs.stdenv.isLinux {
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
    };
}

# Yet Another Anime Game Launcher. _yaagl.nix builds one bundle per game and
# region; the CN variants it also knows about install alongside these without
# clashing, should they ever be wanted.
{
  flake.modules.homeManager.darwin =
    { pkgs, ... }:
    let
      yaagl = pkgs.callPackage ./_yaagl.nix { };
    in
    {
      home.packages = [
        yaagl.yaagl-genshin-os
        yaagl.yaagl-hsr-os
      ];
    };
}

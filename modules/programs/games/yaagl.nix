# Yet Another Anime Game Launcher — opt in per game / region via `yaagl.*`.
{
  flake.modules.homeManager.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # _yaagl.nix returns an attrset of yaagl-<game>-<region> derivations.
      yaaglPkgs = pkgs.callPackage ./_yaagl.nix { };

      gameOption =
        prettyName:
        lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "os"
              "cn"
              "both"
            ]
          );
          default = null;
          description = ''
            ${prettyName} region to install:
              "os"   -> Global / HoYoverse
              "cn"   -> Chinese / miHoYo
              "both" -> both regions (separate app bundles + data dirs, no clash)
              null   -> not installed (default)
          '';
        };

      pickFor =
        game: region:
        if region == "both" then
          [
            "yaagl-${game}-cn"
            "yaagl-${game}-os"
          ]
        else
          [ "yaagl-${game}-${region}" ];

      selected = lib.flatten (
        lib.mapAttrsToList (game: region: if region == null then [ ] else pickFor game region) {
          inherit (config.yaagl) genshin hsr zzz;
        }
      );
    in
    {
      options.yaagl = lib.mkOption {
        type = lib.types.submodule {
          options = {
            genshin = gameOption "Genshin Impact";
            hsr = gameOption "Honkai: Star Rail";
            zzz = gameOption "Zenless Zone Zero";
          };
        };
        default = { };
        description = "Yet Another Anime Game Launcher — per game / region opt-in.";
      };

      config = {
        yaagl = {
          genshin = lib.mkDefault "os";
          hsr = lib.mkDefault "os";
          # zzz = "cn";
        };

        home.packages = lib.mkIf (selected != [ ]) (map (name: yaaglPkgs.${name}) selected);
      };
    };
}

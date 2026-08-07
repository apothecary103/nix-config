{ lib, ... }:
{
  flake.modules.nixos.base = {
    # The bar's battery widget reads UPower rather than sysfs.
    services.upower.enable = true;
  };

  flake.modules.homeManager.linux =
    { pkgs, palette, ... }:
    let
      # Named Colors rather than Palette: QtQuick already exports a `Palette`
      # type, which would shadow the singleton and silently resolve to it.
      colorsQml = pkgs.writeText "Colors.qml" /* qml */ ''
        pragma Singleton

        // QtQuick, not just Quickshell: the `color` value type comes from there.
        import QtQuick
        import Quickshell

        // Generated from the palette in modules/desktop/theme.nix.
        Singleton {
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: hex: "    readonly property color ${name}: \"${hex}\"") palette
        )}
        }
      '';

      shellRoot = pkgs.runCommandLocal "quickshell-shell" { } ''
        mkdir -p $out
        cp -r ${./qml}/. $out/
        cp ${colorsQml} $out/Colors.qml
        cp ${../../../assets/avatar.jpg} $out/avatar.jpg
      '';
    in
    {
      home.packages = [
        pkgs.quickshell
        pkgs.brightnessctl
      ];

      xdg.configFile."quickshell".source = shellRoot;

      systemd.user.services.quickshell = {
        Unit = {
          Description = "quickshell desktop shell";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          # No PATH override: the shell launches desktop entries and shells out
          # to brightnessctl and niri, so it wants the session PATH the
          # compositor imports into the user manager.
          ExecStart = "${lib.getExe pkgs.quickshell} --no-duplicate";
          Restart = "on-failure";
          RestartSec = 2;
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}

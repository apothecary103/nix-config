{ lib, ... }:
{
  flake.modules.nixos.base = {
    # The bar's battery widget reads UPower rather than sysfs.
    services.upower.enable = true;
  };

  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      # Named Colors rather than Palette: QtQuick already exports a `Palette`
      # type, which would shadow the singleton and silently resolve to it.
      colorsQml =
        pkgs.writeText "Colors.qml" # qml
          ''
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
      packages = [
        pkgs.quickshell
        pkgs.brightnessctl
      ];

      xdg.config.files."quickshell".source = shellRoot;

      systemd.services.quickshell = {
        description = "quickshell desktop shell";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];

        serviceConfig = {
          # No PATH override: the shell launches desktop entries and shells out
          # to brightnessctl and niri, so it wants the session PATH the
          # compositor imports into the user manager.
          ExecStart = "${lib.getExe pkgs.quickshell} --no-duplicate";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    };
}

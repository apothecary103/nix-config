{ lib, ... }:
{
  flake.modules.nixos.base = {
    # The bar's battery widget reads UPower rather than sysfs, so it needs no
    # machine-specific device path.
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
        # The OSD drives the backlight through brightnessctl.
        pkgs.brightnessctl
      ];

      # ~/.config/quickshell is a symlink into the store, which also matters on
      # frieren: /home is wiped every boot (see system/preservation.nix), so an
      # unmanaged config there would not survive a reboot.
      xdg.configFile."quickshell".source = shellRoot;

      systemd.user.services.quickshell = {
        Unit = {
          Description = "quickshell desktop shell";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          # No PATH override: the shell shells out to brightnessctl and niri and
          # launches desktop entries, so it wants the session PATH the compositor
          # imports into the user manager.
          ExecStart = "${lib.getExe pkgs.quickshell} --no-duplicate";
          Restart = "on-failure";
          RestartSec = 2;
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}

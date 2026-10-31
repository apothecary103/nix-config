{ lib, ... }:
{
  flake.modules.nixos.base = {
    # The bar's battery reads UPower rather than sysfs.
    services.upower.enable = true;
  };

  # The desktop shell: a menubar flush with the notch, and a "dynamic island"
  # drawn over the notch that grows for the volume and brightness overlay and
  # for track changes. Colours come from the orchard palette; kwm's tags and
  # focused window from its IPC (see river/patches/kwm/0002-ipc.patch).
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      # The theme's own colour names plus the portable surfaces, hues and
      # statuses; the syntax roles (escape, function, ...) aren't legal QML
      # property names and the shell has no use for them. Named Colors because
      # QtQuick already exports a Palette type.
      colours =
        lib.getAttrs [
          "accent"
          "base"
          "mantle"
          "crust"
          "text"
          "surface0"
          "surface1"
          "surface2"
          "overlay0"
          "overlay1"
          "overlay2"
          "subtext0"
          "subtext1"
          "red"
          "orange"
          "yellow"
          "green"
          "aqua"
          "blue"
          "purple"
          "pink"
          "error"
          "warning"
          "info"
          "ok"
        ] palette.named
        // lib.filterAttrs (_: lib.isString) palette.native;

      colorsQml = pkgs.writeText "Colors.qml" ''
        pragma Singleton

        import QtQuick
        import Quickshell

        Singleton {
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: hex: "    readonly property color ${name}: \"${hex}\"") colours
        )}
        }
      '';

      # Follows kwm's state file, which kwm replaces with a rename on change.
      kwmState = pkgs.writeShellApplication {
        name = "kwm-state";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.inotify-tools
        ];
        text = ''
          dir="$XDG_RUNTIME_DIR/kwm"
          until [ -d "$dir" ]; do sleep 0.2; done
          [ -f "$dir/state.json" ] && cat "$dir/state.json"
          inotifywait -mq -e moved_to --format %f "$dir" | while read -r file; do
            if [ "$file" = state.json ]; then cat "$dir/state.json"; fi
          done
        '';
      };

      toolsQml = pkgs.writeText "Tools.qml" ''
        pragma Singleton

        import Quickshell

        Singleton {
            readonly property string kwmState: "${lib.getExe kwmState}"
        }
      '';

      shellRoot = pkgs.runCommandLocal "quickshell-shell" { } ''
        mkdir -p $out
        cp -r ${./qml}/. $out/
        cp ${colorsQml} $out/Colors.qml
        cp ${toolsQml} $out/Tools.qml
        cp ${../../../assets/avatar.jpg} $out/avatar.jpg
      '';
    in
    {
      packages = [ pkgs.quickshell ];

      xdg.config.files."quickshell".source = shellRoot;

      systemd.services.quickshell = {
        description = "Desktop shell";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        # sh for execDetached commands; the session PATH comes from river.
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.quickshell} --no-duplicate";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    };
}

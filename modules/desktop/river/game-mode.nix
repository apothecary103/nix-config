{
  # The trackpad off while a game has focus. libinput's palm rejection can't
  # cover gaming: disable-while-typing only blocks touches that begin while
  # keys are down, a palm resting before or between keypresses gets through,
  # and with the pointer locked any stray motion turns the camera. Games are
  # played with the mouse here, so the pad is simply ignored while one is
  # focused, following kwm's state (see patches/kwm/0002-ipc.patch).
  flake.modules.hjem.linux =
    { lib, pkgs, ... }:
    let
      # Window app-ids, as kwm reports them.
      games = [ "com.mojang.minecraft" ];
      trackpad = "Apple MTP multi-touch";

      kwim = pkgs.callPackage ./_kwim.nix { };

      gameMode = pkgs.writeShellApplication {
        name = "game-mode";
        runtimeInputs = [
          kwim
          pkgs.coreutils
          pkgs.inotify-tools
          pkgs.jq
        ];
        text = ''
          dir="$XDG_RUNTIME_DIR/kwm"
          trackpad=${lib.escapeShellArg trackpad}
          games=${lib.escapeShellArg "|${lib.concatStringsSep "|" games}|"}
          current=""
          watch=""

          pad() {
            [ "$1" = "$current" ] && return
            kwim apply libinput-device -n "$trackpad" --send-event-modes "$1" && current=$1
          }

          restore() {
            kill "$watch" 2>/dev/null || true
            kwim apply libinput-device -n "$trackpad" --send-event-modes enabled
          }

          check() {
            app=$(jq -r '.app_id // ""' "$dir/state.json" 2>/dev/null || true)
            case "$games" in
              *"|$app|"*) pad disabled ;;
              *) pad enabled ;;
            esac
          }

          trap restore EXIT
          trap 'exit' TERM INT HUP

          until [ -d "$dir" ]; do sleep 0.2; done
          check
          # In the background: bash holds traps until a foreground pipeline ends,
          # and this one never does, so stopping the unit would leave the pad off.
          inotifywait -mq -e moved_to --format %f "$dir" | while read -r file; do
            if [ "$file" = state.json ]; then check; fi
          done &
          watch=$!
          wait "$watch"
        '';
      };
    in
    {
      systemd.services.game-mode = {
        description = "Trackpad off while a game has focus";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe gameMode;
          Restart = "on-failure";
        };
      };
    };
}

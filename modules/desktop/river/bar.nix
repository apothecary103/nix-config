{
  # CelestialCrafter's yambar, rebuilt in eww: a flat Overlay bar, 42 px tall
  # with azuki at 20 px. On the left, the tags 14 px apart: azuki draws the
  # rice's box-drawing glyphs as a rose spark (┨) for the ones shown, a muted
  # heart (┻) for the rest and a note (┯) for the tenth, the special tag;
  # tags past the third stay hidden unless shown or occupied. (Its ♡ and ✲
  # are blank.) Then the focused
  # window's app-id. On the right, the volume and the date and time.
  #
  # river 0.5 has no status protocol, so kwm reports its tags and focus through
  # $XDG_RUNTIME_DIR/kwm (see patches/kwm/0002-ipc.patch): clicks write to its
  # control fifo, and kwm-state follows state.json.
  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      # Every state kwm writes, as it replaces state.json.
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

      # The default sink's volume whenever pipewire reports a change, and
      # nothing while there is no sink, as yambar's sink_online did.
      volume = pkgs.writeShellApplication {
        name = "bar-volume";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.pulseaudio
        ];
        text = ''
          emit() {
            pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -om1 '[0-9]*%' | tr -d % || echo
          }
          # pactl exits with the server, so wait for it to come back.
          while :; do
            emit
            pactl subscribe | grep --line-buffered -E "'change' on (sink|server)" | while read -r _; do
              emit
            done || true
            sleep 1
          done
        '';
      };

      control = "echo %s > $XDG_RUNTIME_DIR/kwm/control";
      command = action: builtins.replaceStrings [ "%s" ] [ action ] control;
    in
    {
      packages = [ pkgs.eww ];

      xdg.config.files."eww/eww.yuck".text = ''
        (deflisten kwm :initial '{"tags":[],"app_id":"","title":""}' "${lib.getExe kwmState}")
        (deflisten volume :initial "" "${lib.getExe volume}")

        (defwidget kwm-tag [tag]
          (eventbox
            :visible {tag.focused || tag.occupied || tag.id <= 3 || tag.id == 10}
            :cursor "pointer"
            :onclick "${command "set_output_tag \${tag.id}"}"
            :onrightclick "${command "toggle_output_tag \${tag.id}"}"
            (label
              :class {tag.focused ? "tag focused" : "tag"}
              :text {tag.focused ? "┨" : tag.id == 10 ? "┯" : "┻"})))

        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "42px" :anchor "top center")
          (centerbox :class "bar"
            (box :space-evenly false :halign "start"
              ; Its own box: eww appends a for's children after their siblings.
              (box :space-evenly false
                (for tag in {kwm.tags}
                  (kwm-tag :tag tag)))
              (label :class "app-id" :visible {kwm.app_id != ""} :text {kwm.app_id}))
            (box)
            (box :space-evenly false :halign "end"
              (label :class "volume" :visible {volume != ""} :text "''${volume}%")
              (label :class "clock" :text {formattime(EWW_TIME, "%m/%d/%Y %I:%M %p")}))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        * {
          all: unset;
        }

        .bar {
          min-height: 42px;
          background-color: ${palette.surface.panel};
          color: ${palette.surface.text};
          font-family: "azuki_font";
          font-size: 20px;
        }

        .tag {
          margin-left: 14px;
          color: ${palette.surface.neutral4};
        }

        .tag.focused {
          color: ${palette.ui.accent};
        }

        eventbox:hover .tag {
          color: ${palette.surface.text};
        }

        eventbox:hover .tag.focused {
          color: ${palette.ui.accent};
        }

        .app-id,
        .volume {
          margin: 0 18px;
        }

        .clock {
          margin-right: 14px;
        }
      '';

      systemd.services.eww = {
        description = "Bar";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        # eww runs its scripts and click handlers through sh, which a user
        # unit's PATH does not have.
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.eww} daemon --no-daemonize";
          ExecStartPost = "${lib.getExe pkgs.eww} --no-daemonize open bar";
          Restart = "on-failure";
        };
      };
    };
}

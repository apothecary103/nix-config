{
  flake.modules.homeManager.linux =
    { palette, ... }:
    let
      # Wrap a Nerd Font glyph so it renders in the accent colour while the
      # value next to it keeps the normal foreground. Used by every module so
      # "all icons are blue" stays in one place.
      icon = glyph: "<span foreground='${palette.blue}'>${glyph}</span>";
    in
    {
      programs.waybar = {
        enable = true;

        settings = {
          mainBar = {
            layer = "top";
            position = "top";
            height = 34;
            spacing = 0;

            modules-left = [
              "niri/workspaces"
              "niri/window"
            ];

            modules-center = [ "mpris" ];

            modules-right = [
              "pulseaudio"
              "battery"
              "clock"
            ];

            # Plain workspace numbers — always visible, unlike the previous
            # glyph-only format. Active/inactive colour is handled in CSS.
            "niri/workspaces" = {
              format = "{index}";
            };

            "niri/window" = {
              format = "{app_id}";
              max-length = 50;
              separate-outputs = true;
            };

            # playerctl/MPRIS: play-pause icon + track. Controls whatever MPRIS
            # player is active (mpd via mpdris2-rs). Hidden when nothing plays.
            mpris = {
              format = "${icon "{status_icon}"} {dynamic}";
              status-icons = {
                playing = "󰐊";
                paused = "󰏤";
                stopped = "󰓛";
              };
              dynamic-order = [
                "title"
                "artist"
              ];
              dynamic-len = 40;
              tooltip = false;
            };

            # Icon + value (no "vol"/"bat" word labels). Icon is blue, value is
            # normal text.
            pulseaudio = {
              format = "${icon "{icon}"} {volume}%";
              format-muted = icon "󰝟";
              format-icons = {
                headphone = "󰋋";
                headset = "󰋎";
                default = [
                  "󰕿"
                  "󰖀"
                  "󰕾"
                ];
              };
              tooltip = false;
            };

            battery = {
              format = "${icon "{icon}"} {capacity}%";
              format-charging = "${icon "󰂄"} {capacity}%";
              format-plugged = "${icon "󰚥"} {capacity}%";
              format-icons = [
                "󰁺"
                "󰁻"
                "󰁼"
                "󰁽"
                "󰁾"
                "󰁿"
                "󰂀"
                "󰂁"
                "󰂂"
                "󰁹"
              ];
              states = {
                warning = 30;
                critical = 15;
              };
              tooltip = false;
            };

            clock = {
              format = "${icon ""} {:%H:%M}";
              tooltip-format = "{:%A, %d %B %Y}";
            };
          };
        };

        style = /* css */ ''
          * {
              border: none;
              border-radius: 0;
              min-height: 0;
              margin: 0;
              padding: 0;
              box-shadow: none;
              text-shadow: none;
              transition-property: none;
              font-family: "Maple Mono NF CN", monospace;
              font-size: 14px;
              font-weight: 600;
          }

          /* Slightly translucent so the compositor/wallpaper shows through. */
          window#waybar {
              background-color: alpha(${palette.base}, 0.85);
              color: ${palette.text};
          }

          .modules-left {
              padding-left: 16px;
          }

          .modules-right {
              padding-right: 16px;
          }

          #workspaces button {
              color: ${palette.overlay1};
              padding: 0 8px;
          }

          #workspaces button.active,
          #workspaces button.focused {
              color: ${palette.blue};
          }

          #workspaces button:hover {
              box-shadow: none;
              text-shadow: none;
          }

          #window {
              padding: 0 12px;
              color: ${palette.subtext0};
          }

          #mpris {
              color: ${palette.subtext0};
          }

          #pulseaudio,
          #battery,
          #clock {
              color: ${palette.text};
              padding: 0 10px;
          }

          #clock {
              padding-right: 0;
          }

          #battery.critical:not(.charging) {
              color: ${palette.red};
          }
        '';
      };
    };
}

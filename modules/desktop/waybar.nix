{
  flake.modules.homeManager.linux = { palette, ... }: {
    programs.waybar = {
      enable = true;

      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 34;
          spacing = 0;

          modules-left = [
            "hyprland/workspaces"
            "custom/layout"
            "hyprland/window"
          ];

          modules-center = [ ];

          modules-right = [
            "tray"
            "network"
            "battery"
            "pulseaudio"
            "clock"
          ];

          "hyprland/workspaces" = {
            format = "{name}";
            disable-scroll = true;
            all-outputs = true;
            active-only = false;
            persistent-workspaces = {
              "*" = 9;
            };
          };

          "custom/layout" = {
            exec = "echo '::[]'";
            interval = "once";
            format = "{}";
          };

          "hyprland/window" = {
            format = "{class}";
            max-length = 80;
            rewrite = {
              "com.mitchellh.ghostty" = "ghostty";
            };
          };

          tray = {
            spacing = 8;
          };

          network = {
            format-wifi = "| {essid}";
            format-ethernet = "| eth";
            format-disconnected = "| n/a";
            tooltip = false;
          };

          battery = {
            format = " | bat {capacity}%";
            format-charging = " | chr {capacity}%";
            format-plugged = " | plg {capacity}%";
            tooltip = false;
          };

          pulseaudio = {
            format = " | vol {volume}%";
            format-muted = " | mut";
            tooltip = false;
          };

          clock = {
            format = " | {:%d-%m-%Y | %H:%M:%S}";
            interval = 1;
            tooltip = false;
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

        window#waybar {
            background-color: ${palette.base};
            color: ${palette.text};
        }

        .modules-left {
            padding-left: 20px;
        }

        .modules-right {
            padding-right: 20px;
        }

        #workspaces button {
            background-color: ${palette.base};
            color: ${palette.text};
            padding: 0 10px;

            background-image:
                linear-gradient(${palette.text}, ${palette.text}), /* top edge */
                linear-gradient(${palette.text}, ${palette.text}), /* bottom edge */
                linear-gradient(${palette.text}, ${palette.text}), /* left edge */
                linear-gradient(${palette.text}, ${palette.text}); /* right edge */
            background-size:
                5px 1px, /* top width/height */
                5px 1px, /* bottom width/height */
                1px 5px, /* left width/height */
                1px 5px; /* right width/height */
            background-position:
                2px 2px, /* top x,y */
                2px 6px, /* bottom x,y */
                2px 2px, /* left x,y */
                6px 2px; /* right x,y */
            background-repeat: no-repeat;
        }

        #workspaces button.active {
            background-color: ${palette.blue};
            color: ${palette.base};

            background-image: linear-gradient(${palette.base}, ${palette.base});
            background-size: 5px 5px;
            background-position: 2px 2px;
        }

        #workspaces button.empty {
            background-image: none;
        }

        #workspaces button:hover {
            box-shadow: none;
            text-shadow: none;
        }

        #custom-layout {
            padding: 0 8px;
            color: ${palette.text};
        }

        #window {
            padding: 0 12px;
            background-color: ${palette.blue};
            color: ${palette.base};
        }

        #tray, #network, #battery, #pulseaudio, #clock {
            background-color: ${palette.base};
            color: ${palette.text};
            padding: 0;
        }

        #tray {
            padding-right: 8px;
        }
      '';
    };
  };
}

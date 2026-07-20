{ config, lib, pkgs, ... }:

{
  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 34;
        spacing = 0;

        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ ];
        modules-right = [ "tray" "wireplumber" "battery" "custom/clock" ];

        "hyprland/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
          active-only = false;
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            urgent = "!";
            default = "•";
          };
          persistent-workspaces = {
            "*" = [ 1 2 3 4 5 6 ];
          };
        };

        tray = {
          icon-size = 14;
          spacing = 12;
        };

        wireplumber = {
          format = "<span color='#aca1cf'>󰕾</span> {volume}%";
          format-muted = "<span color='#57565e'>󰖁</span> MUT";
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+";
          on-scroll-down = "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%-";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "<span color='#90b99f'>{icon}</span> {capacity}%";
          format-warning = "<span color='#e6b99d'>{icon}</span> {capacity}%";
          format-critical = "<span color='#f5a191'>{icon}</span> {capacity}%";
          format-charging = "<span color='#90b99f'>󰂄</span> {capacity}%";
          format-plugged = "<span color='#90b99f'></span> {capacity}%";
          format-icons = [ "󰂎" "󰁺" "󰁼" "󰁾" "󰂀" "󰁹" ];
        };

        "custom/clock" = {
          exec = "echo \"<span color='#aca1cf'>󰃭</span> $(date +'%a, %b %e')  <span color='#aca1cf'>󰅐</span> $(date +'%H:%M')\"";
          interval = 30;
          format = "{}";
        };
      };
    };

    style = ''
      @define-color bg       rgba(22, 22, 23, 0.88);
      @define-color bg-alt   #2a2b30;
      @define-color fg       #c9c7cd;
      @define-color fg-dim   #57565e;
      @define-color blue     #aca1cf;
      @define-color red      #f5a191;

      * {
          font-family: "MapleMono NF CN", monospace;
          font-size: 13px;
          font-weight: 700;
          border: none;
          border-radius: 0px; 
          min-height: 0;
          transition: none;
      }

      window#waybar {
          background-color: @bg;
          color: @fg;
          border-bottom: 1px solid @bg-alt;
      }

      .modules-left {
          padding-left: 16px;
      }

      #workspaces button {
          color: @fg-dim;
          padding: 0px 6px;
          margin: 0px;
          border-bottom: 2px solid transparent;
      }

      #workspaces button:hover {
          color: @fg;
          background-color: @bg-alt;
      }

      #workspaces button.active {
          color: @blue;
          border-bottom: 2px solid @blue;
      }

      #workspaces button.urgent {
          color: @red;
          border-bottom: 2px solid @red;
      }

      .modules-right {
          padding-right: 16px;
      }

      #tray,
      #wireplumber,
      #battery,
      #custom-clock {
          color: @fg;
          padding: 0px 12px;
          margin: 0px;
          background-color: transparent;
      }

      #tray {
          padding-right: 14px;
      }

      #custom-clock {
          padding-right: 0px;
      }

      tooltip {
          background: #161617;
          border: 1px solid @bg-alt;
      }
      tooltip label {
          color: @fg;
      }
    '';
  };
}

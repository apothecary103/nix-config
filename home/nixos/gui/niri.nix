{ config, pkgs, inputs, ... }:

{
  imports = [ 
    inputs.niri.homeModules.niri
  ];
    
  programs.niri.settings = {
    debug = {
      render-drm-device = "/dev/dri/renderD128";
    };

    input = {
      keyboard = {
        xkb = {
          # layout = "us,de";
          # options = "grp:win_space_toggle,compose:ralt,ctrl:nocaps";
        };
        numlock = true;
      };

      touchpad = {
        tap = true;
        dwt = true;
        natural-scroll = true;
      };

      mouse = {
        # off = true;
      };

      trackpoint = {
        # off = true;
      };

      # warp-mouse-to-focus = true;
      # focus-follows-mouse.max-scroll-amount = "0%";
    };

    outputs."eDP-1" = {
      scale = 2.0;
      transform.rotation = 0;
      # mode = "1920x1080@120.030";
      # position = { x = 1280; y = 0; };
    };

    layout = {
      gaps = 16;
      center-focused-column = "never";

      preset-column-widths = [
        { proportion = 1.0 / 3.0; }
        { proportion = 0.5; }
        { proportion = 2.0 / 3.0; }
      ];

      default-column-width = { proportion = 0.5; };

      focus-ring = {
        width = 2;
        active.color = "#8aadf4";
        inactive.color = "#505050";
      };

      border = {
        enable = false; 
        width = 4;
        active.color = "#ffc87f";
        inactive.color = "#505050";
      };

      shadow = {
        # enable = true;
        softness = 30;
        spread = 5;
        offset = { x = 0; y = 5; };
        color = "#00000077";
      };
    };

    spawn-at-startup = [
      { command = [ "waybar" ]; }
      { command = [ "awww-daemon" ]; }
    ];

    prefer-no-csd = true;
    screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

    window-rules = [
      {
        matches = [ { app-id = "^org\\.wezfurlong\\.wezterm$"; } ];
        default-column-width = { };
      }
      {
        geometry-corner-radius = {
          top-left = 12.0;
          top-right = 12.0;
          bottom-left = 12.0;
          bottom-right = 12.0;
        };
        clip-to-geometry = true;
      }
      {
        matches = [ { app-id = "firefox$"; title = "^Picture-in-Picture$"; } ];
        open-floating = true;
      }
      {
        matches = [ { app-id = "com.mitchellh.ghostty"; } ];
        draw-border-with-background = false;
      }
    ];

    binds = {
      "Mod+Shift+Slash".action.show-hotkey-overlay = [ ];
      "Mod+T".action.spawn = "ghostty";
      "Mod+D".action.spawn = "fuzzel";
      "Super+Alt+L".action.spawn = "swaylock";

      "Super+Alt+S" = {
        action.spawn = [ "sh" "-c" "pkill orca || exec orca" ];
        allow-when-locked = true;
      };

      "XF86AudioRaiseVolume" = {
        action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+" ];
        allow-when-locked = true;
      };
      "XF86AudioLowerVolume" = {
        action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-" ];
        allow-when-locked = true;
      };
      "XF86AudioMute" = {
        action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ];
        allow-when-locked = true;
      };
      "XF86AudioMicMute" = {
        action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ];
        allow-when-locked = true;
      };

      "XF86MonBrightnessUp" = {
        action.spawn = [ "brightnessctl" "--class=backlight" "set" "+10%" ];
        allow-when-locked = true;
      };
      "XF86MonBrightnessDown" = {
        action.spawn = [ "brightnessctl" "--class=backlight" "set" "10%-" ];
        allow-when-locked = true;
      };

      "Mod+O".action.toggle-overview = [ ];
      "Mod+Q".action.close-window = [ ];

      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Down".action.focus-window-down = [ ];
      "Mod+Up".action.focus-window-up = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      "Mod+H".action.focus-column-left = [ ];
      "Mod+J".action.focus-window-down = [ ];
      "Mod+K".action.focus-window-up = [ ];
      "Mod+L".action.focus-column-right = [ ];

      "Mod+Ctrl+Left".action.move-column-left = [ ];
      "Mod+Ctrl+Down".action.move-window-down = [ ];
      "Mod+Ctrl+Up".action.move-window-up = [ ];
      "Mod+Ctrl+Right".action.move-column-right = [ ];
      "Mod+Ctrl+H".action.move-column-left = [ ];
      "Mod+Ctrl+J".action.move-window-down = [ ];
      "Mod+Ctrl+K".action.move-window-up = [ ];
      "Mod+Ctrl+L".action.move-column-right = [ ];

      "Mod+Home".action.focus-column-first = [ ];
      "Mod+End".action.focus-column-last = [ ];
      "Mod+Ctrl+Home".action.move-column-to-first = [ ];
      "Mod+Ctrl+End".action.move-column-to-last = [ ];

      "Mod+Shift+Left".action.focus-monitor-left = [ ];
      "Mod+Shift+Down".action.focus-monitor-down = [ ];
      "Mod+Shift+Up".action.focus-monitor-up = [ ];
      "Mod+Shift+Right".action.focus-monitor-right = [ ];

      "Mod+Page_Down".action.focus-workspace-down = [ ];
      "Mod+Page_Up".action.focus-workspace-up = [ ];
      "Mod+U".action.focus-workspace-down = [ ];
      "Mod+I".action.focus-workspace-up = [ ];

      "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = [ ];
      "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = [ ];
      "Mod+Ctrl+U".action.move-column-to-workspace-down = [ ];
      "Mod+Ctrl+I".action.move-column-to-workspace-up = [ ];

      "Mod+WheelScrollDown" = { action.focus-workspace-down = [ ]; cooldown-ms = 150; };
      "Mod+WheelScrollUp" = { action.focus-workspace-up = [ ]; cooldown-ms = 150; };

      # Fixed: Using direct values instead of .index 
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+6".action.focus-workspace = 6;
      "Mod+7".action.focus-workspace = 7;
      "Mod+8".action.focus-workspace = 8;
      "Mod+9".action.focus-workspace = 9;

      # Fixed: Using direct values instead of .index
      "Mod+Ctrl+1".action.move-column-to-workspace = 1;
      "Mod+Ctrl+2".action.move-column-to-workspace = 2;
      "Mod+Ctrl+3".action.move-column-to-workspace = 3;
      "Mod+Ctrl+4".action.move-column-to-workspace = 4;
      "Mod+Ctrl+5".action.move-column-to-workspace = 5;
      "Mod+Ctrl+6".action.move-column-to-workspace = 6;
      "Mod+Ctrl+7".action.move-column-to-workspace = 7;
      "Mod+Ctrl+8".action.move-column-to-workspace = 8;
      "Mod+Ctrl+9".action.move-column-to-workspace = 9;

      "Mod+BracketLeft".action.consume-or-expel-window-left = [ ];
      "Mod+BracketRight".action.consume-or-expel-window-right = [ ];
      "Mod+Comma".action.consume-window-into-column = [ ];
      "Mod+Period".action.expel-window-from-column = [ ];

      "Mod+R".action.switch-preset-column-width = [ ];
      "Mod+Shift+R".action.switch-preset-window-height = [ ];
      "Mod+Ctrl+R".action.reset-window-height = [ ];
      "Mod+F".action.maximize-column = [ ];
      "Mod+Shift+F".action.fullscreen-window = [ ];
      "Mod+C".action.center-column = [ ];

      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";

      "Mod+V".action.toggle-window-floating = [ ];
      "Mod+W".action.toggle-column-tabbed-display = [ ];

      "Mod+S".action.screenshot = [ ];
      "Mod+Shift+S".action.screenshot-screen = [ ];
      "Mod+Alt+S".action.screenshot-window = [ ];

      "Mod+Escape" = {
        action.toggle-keyboard-shortcuts-inhibit = [ ];
        allow-inhibiting = false;
      };

      "Mod+Shift+E".action.quit = [ ];
      "Ctrl+Alt+Delete".action.quit = [ ];
      "Mod+Shift+P".action.power-off-monitors = [ ];
    };
  };
}

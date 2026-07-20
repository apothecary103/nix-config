{ pkgs, ... }:

let
  # Catppuccin Macchiato Palette
  macchiato = {
    blue      = "#8caaee";
    lavender  = "#babbf1";
    sapphire  = "#7dc4e4";
    sky       = "#91dced";
    surface1  = "#494d64";
    surface2  = "#5b6078";
    base      = "#24273a";
    text      = "#cad3f5";
  };
in
{
  home.packages = with pkgs; [
    kitty   
    fuzzel  
  ];

  # Basic Fuzzel config to match Macchiato
  programs.fuzzel.settings = {
    main = {
      terminal = "${pkgs.kitty}/bin/kitty";
      font = "Maple Mono NF CN:size=11";
    };
    colors = {
      background = "24273add";
      text = "cad3f5ff";
      match = "8caaeeff";
      selection = "5b6078ff";
      selection-text = "cad3f5ff";
      border = "8caaeetf";
    };
  };

  programs.niri.settings = {
    # Inputs
    input = {
      keyboard.repeat-delay = 250;
      keyboard.repeat-rate = 30;
      touchpad.tap = true;
    };

    # Layout & Catppuccin Macchiato Borders
    layout = {
      gaps = 12;
      border = {
        enable = true;
        width = 4;
        # Active: Blue to Lavender Gradient
        active.gradient = {
          from = macchiato.blue;
          to = macchiato.lavender;
          angle = 45;
        };
        # Inactive: Subtle Surface
        inactive.color = macchiato.surface1;
      };
      focus-ring.enable = false;
    };

    # Keybindings
    binds = {
      # Terminal & Launcher
      "Mod+Return".action.spawn = [ "kitty" ];
      "Mod+D".action.spawn = [ "fuzzel" ];

      # Mod + S: Niri built-in screenshot (Full view)
      # Note: Niri saves these to your XDG Screenshots folder by default
      "Mod+S".action.screenshot = [];
      
      # Mod + Shift + S: Niri built-in screenshot-screen (Focused Monitor)
      "Mod+Shift+S".action.screenshot-screen = [];
      
      # Mod + Alt + S: For the focused window specifically
      "Mod+Alt+S".action.screenshot-window = [];

      # Window Management
      "Mod+Q".action.close-window = [];
      "Mod+Left".action.focus-column-left = [];
      "Mod+Right".action.focus-column-right = [];
      "Mod+Down".action.focus-window-down = [];
      "Mod+Up".action.focus-window-up = [];
      
      "Mod+Ctrl+Left".action.move-column-left = [];
      "Mod+Ctrl+Right".action.move-column-right = [];
      
      "Mod+F".action.maximize-column = [];
      "Mod+Shift+F".action.fullscreen-window = [];
      "Mod+C".action.center-column = [];

      # Workspaces (1-9)
      "Mod+1".action.focus-workspace = [ 1 ];
      "Mod+2".action.focus-workspace = [ 2 ];
      "Mod+3".action.focus-workspace = [ 3 ];
      "Mod+Shift+1".action.move-column-to-workspace = [ 1 ];
      "Mod+Shift+2".action.move-column-to-workspace = [ 2 ];
      "Mod+Shift+3".action.move-column-to-workspace = [ 3 ];

      # Scrolling columns
      "Mod+WheelScrollDown".action.focus-column-right = [];
      "Mod+WheelScrollUp".action.focus-column-left = [];

      # System
      "Mod+Shift+E".action.quit = [];
    };

    # Window Rules (Example: make floating windows behave)
    window-rules = [
      {
        matches = [{ is-floating = true; }];
        default-column-width = { proportion = 0.5; };
      }
    ];
  };
}

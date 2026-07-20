{  lib, ... }:

let
  mainMod = "SUPER";
  terminal = "wezterm";
  fileManager = "nautilus";
  menu = "fuzzel";

  lua = lib.generators.mkLuaInline;

in {
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";

    settings = {
      
      # ------------------
      # ---- MONITORS ----
      # ------------------
      monitor = [
        {
          output = "eDP-1";
          mode = "preferred";
          position = "auto";
          scale = "auto";
          bitdepth = 10;
          cm = "dp3";
        }
      ];

      # -------------------
      # ---- AUTOSTART ----
      # -------------------
      on = [
        {
          _args = [
            "hyprland.start"
            (lua ''function () hl.exec_cmd("waybar & awww-daemon") end'')
          ];
        }
      ];

      # -------------------------------
      # ---- ENVIRONMENT VARIABLES ----
      # -------------------------------
      env = [
        { _args = [ "XCURSOR_SIZE" "24" ]; }
        { _args = [ "HYPRCURSOR_SIZE" "24" ]; }
        { _args = [ "XCURSOR_THEME" "WhiteSur-cursors" ]; }
        { _args = [ "HYPRCURSOR_THEME" "WhiteSur-cursors" ]; }
      ];

      # -----------------------
      # ----- PERMISSIONS -----
      # -----------------------
      # Uncomment to apply permissions
      # ecosystem = { enforce_permissions = true; };
      # permission = [
      #   { _args = [ "/usr/(bin|local/bin)/grim" "screencopy" "allow" ]; }
      #   { _args = [ "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland" "screencopy" "allow" ]; }
      #   { _args = [ "/usr/(bin|local/bin)/hyprpm" "plugin" "allow" ]; }
      # ];

      # -----------------------
      # ---- LOOK AND FEEL ----
      # -----------------------
      config = {
        general = {
          gaps_in = 5;
          gaps_out = 20;
          border_size = 0;
          col = {
            active_border = { colors = [ "rgba(33ccffee)" "rgba(00ff99ee)" ]; angle = 45; };
            inactive_border = "rgba(595959aa)";
          };
          resize_on_border = false;
          allow_tearing = false;
          layout = "scrolling";
        };

        decoration = {
          rounding = 7;
          rounding_power = 3;
          active_opacity = 1.0;
          inactive_opacity = 1.0;
          shadow = {
            enabled = false;
            range = 4;
            render_power = 3;
            color = lua "0xee1a1a1a";
          };
          blur = {
            enabled = true;
            size = 3;
            passes = 3;
            vibrancy = 0.1696;
          };
        };

        animations = {
          enabled = true;
        };

        dwindle = {
          preserve_split = true;
        };

        master = {
          new_status = "master";
        };

        scrolling = {
          fullscreen_on_one_column = true;
        };

        misc = {
          force_default_wallpaper = -1;
          disable_hyprland_logo = false;
        };

        input = {
          kb_layout = "us";
          kb_variant = "";
          kb_model = "";
          kb_options = "";
          kb_rules = "";
          follow_mouse = 1;
          sensitivity = 0;
          touchpad = {
            natural_scroll = false;
          };
        };
      };

      # -------------------
      # ---- ANIMATIONS ---
      # -------------------
      curve = [
        { _args = [ "easeOutQuint"   { type = "bezier"; points = [ [0.23 1] [0.32 1] ]; } ]; }
        { _args = [ "easeInOutCubic" { type = "bezier"; points = [ [0.65 0.05] [0.36 1] ]; } ]; }
        { _args = [ "linear"         { type = "bezier"; points = [ [0 0] [1 1] ]; } ]; }
        { _args = [ "almostLinear"   { type = "bezier"; points = [ [0.5 0.5] [0.75 1] ]; } ]; }
        { _args = [ "quick"          { type = "bezier"; points = [ [0.15 0] [0.1 1] ]; } ]; }
        { _args = [ "easy"           { type = "spring"; mass = 1; stiffness = 71.2633; dampening = 15.8273644; } ]; }
      ];

      animation = [
        { leaf = "global";        enabled = true; speed = 10;   bezier = "default"; }
        { leaf = "border";        enabled = true; speed = 5.39; bezier = "easeOutQuint"; }
        { leaf = "windows";       enabled = true; speed = 4.79; spring = "easy"; }
        { leaf = "windowsIn";     enabled = true; speed = 4.1;  spring = "easy";         style = "popin 87%"; }
        { leaf = "windowsOut";    enabled = true; speed = 1.49; bezier = "linear";       style = "popin 87%"; }
        { leaf = "fadeIn";        enabled = true; speed = 1.73; bezier = "almostLinear"; }
        { leaf = "fadeOut";       enabled = true; speed = 1.46; bezier = "almostLinear"; }
        { leaf = "fade";          enabled = true; speed = 3.03; bezier = "quick"; }
        { leaf = "layers";        enabled = true; speed = 3.81; bezier = "easeOutQuint"; }
        { leaf = "layersIn";      enabled = true; speed = 4;    bezier = "easeOutQuint"; style = "fade"; }
        { leaf = "layersOut";     enabled = true; speed = 1.5;  bezier = "linear";       style = "fade"; }
        { leaf = "fadeLayersIn";  enabled = true; speed = 1.79; bezier = "almostLinear"; }
        { leaf = "fadeLayersOut"; enabled = true; speed = 1.39; bezier = "almostLinear"; }
        { leaf = "workspaces";    enabled = true; speed = 1.94; bezier = "almostLinear"; style = "fade"; }
        { leaf = "workspacesIn";  enabled = true; speed = 1.21; bezier = "almostLinear"; style = "fade"; }
        { leaf = "workspacesOut"; enabled = true; speed = 1.94; bezier = "almostLinear"; style = "fade"; }
        { leaf = "zoomFactor";    enabled = true; speed = 7;    bezier = "quick"; }
      ];

      # ----------------------
      # ---- INPUT DEVICES ---
      # ----------------------
      gesture = [
        { fingers = 3; direction = "horizontal"; action = "workspace"; }
      ];

      device = [
        { name = "epic-mouse-v1"; sensitivity = -0.5; }
      ];

      # ---------------------
      # ---- KEYBINDINGS ----
      # ---------------------
      bind = [
        { _args = [ "${mainMod} + Q" (lua "hl.dsp.exec_cmd('${terminal}')") ]; }
        { _args = [ "${mainMod} + C" (lua "hl.dsp.window.close()") ]; }
        { _args = [ "${mainMod} + M" (lua ''hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")'') ]; }
        { _args = [ "${mainMod} + E" (lua "hl.dsp.exec_cmd('${fileManager}')") ]; }
        { _args = [ "${mainMod} + V" (lua ''hl.dsp.window.float({ action = "toggle" })'') ]; }
        { _args = [ "${mainMod} + R" (lua "hl.dsp.exec_cmd('${menu}')") ]; }
        { _args = [ "${mainMod} + P" (lua "hl.dsp.window.pseudo()") ]; }
        { _args = [ "${mainMod} + J" (lua ''hl.dsp.layout("togglesplit")'') ]; }

        # Focus
        { _args = [ "${mainMod} + left"  (lua ''hl.dsp.focus({ direction = "left" })'') ]; }
        { _args = [ "${mainMod} + right" (lua ''hl.dsp.focus({ direction = "right" })'') ]; }
        { _args = [ "${mainMod} + up"    (lua ''hl.dsp.focus({ direction = "up" })'') ]; }
        { _args = [ "${mainMod} + down"  (lua ''hl.dsp.focus({ direction = "down" })'') ]; }

        # Mouse Workspace
        { _args = [ "${mainMod} + mouse_down" (lua ''hl.dsp.focus({ workspace = "e+1" })'') ]; }
        { _args = [ "${mainMod} + mouse_up"   (lua ''hl.dsp.focus({ workspace = "e-1" })'') ]; }

        # Mouse Drag/Resize
        { _args = [ "${mainMod} + mouse:272" (lua "hl.dsp.window.drag()")   { mouse = true; } ]; }
        { _args = [ "${mainMod} + mouse:273" (lua "hl.dsp.window.resize()") { mouse = true; } ]; }

        # Multimedia Keys
        { _args = [ "XF86AudioRaiseVolume"  (lua ''hl.dsp.exec_cmd("swayosd-client --output-volume raise")'')       { locked = true; repeating = true; } ]; }
        { _args = [ "XF86AudioLowerVolume"  (lua ''hl.dsp.exec_cmd("swayosd-client --output-volume lower")'')       { locked = true; repeating = true; } ]; }
        { _args = [ "XF86AudioMute"         (lua ''hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle")'') { locked = true; repeating = true; } ]; }
        { _args = [ "XF86AudioMicMute"      (lua ''hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle")'')  { locked = true; repeating = true; } ]; }
        { _args = [ "XF86MonBrightnessUp"   (lua ''hl.dsp.exec_cmd("swayosd-client --brightness raise")'')          { locked = true; repeating = true; } ]; }
        { _args = [ "XF86MonBrightnessDown" (lua ''hl.dsp.exec_cmd("swayosd-client --brightness lower")'')          { locked = true; repeating = true; } ]; }

        # Playerctl
        { _args = [ "XF86AudioNext"  (lua ''hl.dsp.exec_cmd("playerctl next")'')       { locked = true; } ]; }
        { _args = [ "XF86AudioPause" (lua ''hl.dsp.exec_cmd("playerctl play-pause")'') { locked = true; } ]; }
        { _args = [ "XF86AudioPlay"  (lua ''hl.dsp.exec_cmd("playerctl play-pause")'') { locked = true; } ]; }
        { _args = [ "XF86AudioPrev"  (lua ''hl.dsp.exec_cmd("playerctl previous")'')   { locked = true; } ]; }

        # Screenshots
        { _args = [ "${mainMod} + S"         (lua ''hl.dsp.exec_cmd("grim - | wl-copy")'') ]; }
        { _args = [ "${mainMod} + SHIFT + S" (lua ''hl.dsp.exec_cmd('grim -g "$(slurp -d)" - | wl-copy')'') ]; }

      ] ++ (
        # Idiomatic Nix list generation for Workspaces 1-10
        builtins.concatLists (builtins.genList (i:
          let
            workspace = i + 1;
            key = if workspace == 10 then "0" else toString workspace;
          in [
            { _args = [ "${mainMod} + ${key}"         (lua "hl.dsp.focus({ workspace = ${toString workspace} })") ]; }
            { _args = [ "${mainMod} + SHIFT + ${key}" (lua "hl.dsp.window.move({ workspace = ${toString workspace} })") ]; }
          ]
        ) 10)
      );

      # --------------------------------
      # ---- WINDOWS AND WORKSPACES ----
      # --------------------------------
      window_rule = [
        {
          name = "suppress-maximize-events";
          match = { class = ".*"; };
          suppress_event = "maximize";
        }
        {
          name = "fix-xwayland-drags";
          match = { class = "^$"; title = "^$"; xwayland = true; float = true; fullscreen = false; pin = false; };
          no_focus = true;
        }
        {
          name = "move-hyprland-run";
          match = { class = "hyprland-run"; };
          move = "20 monitor_h-120";
          float = true;
        }
      ];

      layer_rule = [
        { match = { namespace = "waybar"; }; blur = true; }
        { match = { namespace = "notifications"; }; blur = true; ignore_alpha = 0.5; }
        { match = { namespace = "swayosd"; }; blur = true; }
        { match = { namespace = "launcher"; }; blur = true; ignore_alpha = 0.5; }
      ];

    };
  };
}

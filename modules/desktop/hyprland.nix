{
  # Make desktop entries and portal definitions visible to the session.
  flake.modules.nixos.base.environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  flake.modules.homeManager.linux =
    { lib, palette, ... }:
    let
      mainMod = "SUPER";
      terminal = "ghostty";
      fileManager = "yazi";
      menu = "qs ipc call launcher toggle";

      lua = lib.generators.mkLuaInline;
      hex = lib.removePrefix "#";
    in
    {
      wayland.windowManager.hyprland = {
        enable = true;
        configType = "lua";

        settings = {
          # ---- MONITORS ----
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

          # ---- AUTOSTART ----
          on = [
            {
              _args = [
                "hyprland.start"
                # quickshell already runs as a home-manager user service bound to
                # the graphical session (same as under niri), so only the
                # wallpaper daemon needs starting here.
                (lua ''function () hl.exec_cmd("awww-daemon") end'')
              ];
            }
          ];

          # ---- ENVIRONMENT VARIABLES ----
          env = [
            {
              _args = [
                "XCURSOR_SIZE"
                "24"
              ];
            }
            {
              _args = [
                "HYPRCURSOR_SIZE"
                "24"
              ];
            }
            {
              _args = [
                "XCURSOR_THEME"
                "WhiteSur-cursors"
              ];
            }
            {
              _args = [
                "HYPRCURSOR_THEME"
                "WhiteSur-cursors"
              ];
            }
          ];

          # ---- LOOK AND FEEL ----
          config = {
            general = {
              gaps_in = 5;
              gaps_out = 20;
              border_size = 2;
              col = {
                # Catppuccin accent (blue) on the active border, faded down so it
                # reads as a subtle outline rather than a glow; the inactive
                # border fades further into a low-alpha surface tone.
                active_border = "rgba(${hex palette.surface1}cc)";
                inactive_border = "rgba(${hex palette.surface1}88)";
              };
              resize_on_border = false;
              allow_tearing = true;
              layout = "scrolling";
            };

            decoration = {
              rounding = 8;
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
                passes = 1;
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

            # Direction-based focus/move (below) cross monitor edges on their
            # own, so niri's separate "move column to monitor" binds aren't
            # needed here.
            binds = {
              window_direction_monitor_fallback = true;
            };

            misc = {
              force_default_wallpaper = -1;
              disable_hyprland_logo = false;
            };

            input = {
              kb_layout = "us";
              kb_variant = "";
              kb_model = "";
              kb_options = "compose:ralt";
              kb_rules = "";
              follow_mouse = 1;
              sensitivity = 0;
              touchpad = {
                natural_scroll = false;
              };
            };
          };

          # ---- ANIMATIONS ----
          # Transcribed from niri's defaults (see the niri wiki's Animations
          # page), because niri is the reference for how this machine should
          # feel; Hyprland's own stock set is far more languid. niri uses either
          # a critically damped spring or a 150ms ease-out for everything, and
          # its spring mass is hardcoded to 1. Hyprland's `dampening` is the raw
          # damping coefficient rather than a ratio, so it is derived as
          # c = 2 * damping-ratio * sqrt(mass * stiffness).
          #
          #   niri                        stiffness/duration   leaf
          #   window-movement, -resize    spring 800           windows
          #   horizontal-view-movement    spring 800           windowsMove
          #   workspace-switch            spring 1000          workspaces
          #   overview-open-close         spring 800           zoomFactor
          #   window-open                 150ms ease-out-expo  windowsIn
          #   window-close                150ms ease-out-quad  windowsOut
          #
          # windowsMove is spelled out rather than left to inherit from windows:
          # under the scrolling layout it fires on every focus change, so it is
          # the animation that decides whether the whole session feels sluggish.
          curve = [
            {
              _args = [
                "niriMovement"
                {
                  type = "spring";
                  mass = 1;
                  stiffness = 800;
                  dampening = 56.5685425;
                }
              ];
            }
            {
              _args = [
                "niriWorkspace"
                {
                  type = "spring";
                  mass = 1;
                  stiffness = 1000;
                  dampening = 63.2455532;
                }
              ];
            }
            # niri implements the real easing functions; these are the standard
            # cubic-bezier approximations of them (as on easings.net).
            {
              _args = [
                "easeOutExpo"
                {
                  type = "bezier";
                  points = [
                    [
                      0.16
                      1
                    ]
                    [
                      0.3
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "easeOutQuad"
                {
                  type = "bezier";
                  points = [
                    [
                      0.5
                      1
                    ]
                    [
                      0.89
                      1
                    ]
                  ];
                }
              ];
            }
          ];

          # `speed` is in deciseconds (1 = 100ms). It is kept in step with each
          # spring's settling time so the result matches niri either way, since
          # a spring's duration comes from its own physics.
          animation = [
            {
              leaf = "global";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
            }
            {
              leaf = "windows";
              enabled = true;
              speed = 2;
              spring = "niriMovement";
            }
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 2;
              spring = "niriMovement";
            }
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutExpo";
              style = "popin 90%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
              style = "popin 90%";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
            }
            {
              leaf = "fadeIn";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutExpo";
            }
            {
              leaf = "fadeOut";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
            }
            {
              leaf = "workspaces";
              enabled = true;
              speed = 2;
              spring = "niriWorkspace";
              # niri's workspaces are stacked vertically, so a vertical slide
              # rather than Hyprland's default cross-fade.
              style = "slidevert";
            }
            {
              leaf = "zoomFactor";
              enabled = true;
              speed = 2;
              spring = "niriMovement";
            }

            # niri animates neither its focus ring nor layer-shell surfaces, so
            # focus feedback is instant and quickshell's own QML animations (see
            # quickshell/qml/osd/Osd.qml) are the only thing moving its surfaces
            # — a compositor fade on top of those reads as a double animation.
            {
              leaf = "border";
              enabled = false;
            }
            {
              leaf = "layers";
              enabled = false;
            }
            {
              leaf = "layersIn";
              enabled = false;
            }
            {
              leaf = "layersOut";
              enabled = false;
            }
            {
              leaf = "fadeLayersIn";
              enabled = false;
            }
            {
              leaf = "fadeLayersOut";
              enabled = false;
            }
          ];

          # ---- INPUT DEVICES ---
          device = [
            {
              name = "epic-mouse-v1";
              sensitivity = -0.5;
            }
          ];

          # ---- KEYBINDINGS ----
          # Mirrors niri's binds (modules/desktop/niri.nix) onto Hyprland's
          # scrolling layout. A few niri actions have no clean Hyprland
          # equivalent and are intentionally left unbound: show-hotkey-overlay,
          # toggle-overview, focus/move-column-first/last, the preset/reset
          # window-height binds, switch-focus-between-floating-and-tiling,
          # move-column-to-monitor-* (superseded by binds.window_direction_
          # monitor_fallback below), workspace reordering, and toggle-
          # keyboard-shortcuts-inhibit.
          bind = [
            # Core App Launching & State
            {
              _args = [
                "${mainMod} + T"
                (lua "hl.dsp.exec_cmd('${terminal}')")
              ];
            }
            {
              _args = [
                "${mainMod} + D"
                (lua "hl.dsp.exec_cmd('${menu}')")
              ];
            }
            {
              _args = [
                "${mainMod} + ALT + L"
                (lua "hl.dsp.exec_cmd('swaylock')")
              ];
            }
            {
              _args = [
                "${mainMod} + E"
                (lua "hl.dsp.exec_cmd('${fileManager}')")
              ];
            }
            {
              _args = [
                "${mainMod} + P"
                (lua "hl.dsp.window.pseudo()")
              ];
            }
            {
              _args = [
                "${mainMod} + Q"
                (lua "hl.dsp.window.close()")
              ];
            }

            # Window Sizing & Screen States (Niri 1:1)
            {
              _args = [
                "${mainMod} + F"
                (lua ''hl.dsp.layout("fit active")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + F"
                (lua ''hl.dsp.window.fullscreen({ action = "toggle" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + M"
                (lua ''hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + F"
                (lua ''hl.dsp.layout("fit expand")'')
              ];
            }
            {
              _args = [
                "${mainMod} + C"
                (lua ''hl.dsp.layout("center")'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + C"
                (lua ''hl.dsp.layout("fit visible")'')
              ];
            }
            {
              _args = [
                "${mainMod} + V"
                (lua ''hl.dsp.window.float({ action = "toggle" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + W"
                (lua "hl.dsp.group.toggle()")
              ];
            }

            # Column Manipulation (Niri Consume/Expel style)
            {
              _args = [
                "${mainMod} + bracketleft"
                (lua ''hl.dsp.layout("consume_or_expel prev")'')
              ];
            }
            {
              _args = [
                "${mainMod} + bracketright"
                (lua ''hl.dsp.layout("consume_or_expel next")'')
              ];
            }
            {
              _args = [
                "${mainMod} + comma"
                (lua ''hl.dsp.layout("consume")'')
              ];
            }
            {
              _args = [
                "${mainMod} + period"
                (lua ''hl.dsp.layout("expel")'')
              ];
            }

            # Focus Navigation (Arrows)
            {
              _args = [
                "${mainMod} + left"
                (lua ''hl.dsp.focus({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + right"
                (lua ''hl.dsp.focus({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + up"
                (lua ''hl.dsp.focus({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + down"
                (lua ''hl.dsp.focus({ direction = "down" })'')
              ];
            }

            # Focus Navigation (Vim Keys - Niri Defaults)
            {
              _args = [
                "${mainMod} + H"
                (lua ''hl.dsp.focus({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + L"
                (lua ''hl.dsp.focus({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + K"
                (lua ''hl.dsp.focus({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + J"
                (lua ''hl.dsp.focus({ direction = "down" })'')
              ];
            }

            # Move Column/Window (Arrows)
            {
              _args = [
                "${mainMod} + CTRL + left"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + right"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + up"
                (lua ''hl.dsp.window.move({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + down"
                (lua ''hl.dsp.window.move({ direction = "down" })'')
              ];
            }

            # Move Column/Window (Vim Keys)
            {
              _args = [
                "${mainMod} + CTRL + H"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + L"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + K"
                (lua ''hl.dsp.window.move({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + J"
                (lua ''hl.dsp.window.move({ direction = "down" })'')
              ];
            }

            # Monitor Focus (Arrows + Vim Keys)
            {
              _args = [
                "${mainMod} + SHIFT + left"
                (lua ''hl.dsp.focus({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + right"
                (lua ''hl.dsp.focus({ monitor = "r" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + up"
                (lua ''hl.dsp.focus({ monitor = "u" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + down"
                (lua ''hl.dsp.focus({ monitor = "d" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + H"
                (lua ''hl.dsp.focus({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + L"
                (lua ''hl.dsp.focus({ monitor = "r" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + K"
                (lua ''hl.dsp.focus({ monitor = "u" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + J"
                (lua ''hl.dsp.focus({ monitor = "d" })'')
              ];
            }

            # Column Width Presets (Niri R keys)
            {
              _args = [
                "${mainMod} + R"
                (lua ''hl.dsp.layout("colresize +conf")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + R"
                (lua ''hl.dsp.layout("colresize -conf")'')
              ];
            }

            # Resize Column Width / Window Height (Niri Minus/Equal keys)
            {
              _args = [
                "${mainMod} + minus"
                (lua ''hl.dsp.layout("colresize -0.1")'')
              ];
            }
            {
              _args = [
                "${mainMod} + equal"
                (lua ''hl.dsp.layout("colresize +0.1")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + minus"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 -10%")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + equal"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 10%")'')
              ];
            }

            # Lateral Workspace / Column Scrolling (Niri PageUp/Down + U/I)
            {
              _args = [
                "${mainMod} + Page_Down"
                (lua ''hl.dsp.focus({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + Page_Up"
                (lua ''hl.dsp.focus({ workspace = "m-1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + U"
                (lua ''hl.dsp.focus({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + I"
                (lua ''hl.dsp.focus({ workspace = "m-1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + Page_Down"
                (lua ''hl.dsp.window.move({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + Page_Up"
                (lua ''hl.dsp.window.move({ workspace = "m-1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + U"
                (lua ''hl.dsp.window.move({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + I"
                (lua ''hl.dsp.window.move({ workspace = "m-1" })'')
              ];
            }

            # Niri Mouse Wheel behavior: vertical wheel scrolls workspaces,
            # horizontal wheel scrolls columns.
            {
              _args = [
                "${mainMod} + mouse_down"
                (lua ''hl.dsp.focus({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + mouse_up"
                (lua ''hl.dsp.focus({ workspace = "m-1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + mouse_down"
                (lua ''hl.dsp.window.move({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + mouse_up"
                (lua ''hl.dsp.window.move({ workspace = "m-1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + mouse_right"
                (lua ''hl.dsp.focus({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + mouse_left"
                (lua ''hl.dsp.focus({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + mouse_right"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + mouse_left"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + mouse_down"
                (lua ''hl.dsp.focus({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + mouse_up"
                (lua ''hl.dsp.focus({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + SHIFT + mouse_down"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + SHIFT + mouse_up"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }

            # Mouse Drag/Resize
            {
              _args = [
                "${mainMod} + mouse:272"
                (lua "hl.dsp.window.drag()")
                { mouse = true; }
              ];
            }
            {
              _args = [
                "${mainMod} + mouse:273"
                (lua "hl.dsp.window.resize()")
                { mouse = true; }
              ];
            }

            # Multimedia Keys
            {
              _args = [
                "XF86AudioRaiseVolume"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd volumeUp")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86AudioLowerVolume"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd volumeDown")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86AudioMute"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd muteToggle")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86AudioMicMute"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd micMuteToggle")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86MonBrightnessUp"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd brightnessUp")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86MonBrightnessDown"
                (lua ''hl.dsp.exec_cmd("qs ipc call osd brightnessDown")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }

            # Playerctl
            {
              _args = [
                "XF86AudioNext"
                (lua ''hl.dsp.exec_cmd("playerctl next")'')
                { locked = true; }
              ];
            }
            {
              _args = [
                "XF86AudioPause"
                (lua ''hl.dsp.exec_cmd("playerctl play-pause")'')
                { locked = true; }
              ];
            }
            {
              _args = [
                "XF86AudioPlay"
                (lua ''hl.dsp.exec_cmd("playerctl play-pause")'')
                { locked = true; }
              ];
            }
            {
              _args = [
                "XF86AudioPrev"
                (lua ''hl.dsp.exec_cmd("playerctl previous")'')
                { locked = true; }
              ];
            }

            # Screenshots (Niri Shift+3/4/5 + Print fallbacks)
            {
              _args = [
                "${mainMod} + SHIFT + 3"
                (lua ''hl.dsp.exec_cmd("grim - | wl-copy -t image/png")'')
              ];
            }
            {
              _args = [
                "Print"
                (lua ''hl.dsp.exec_cmd("grim - | wl-copy -t image/png")'')
              ];
            }
            {
              _args = [
                "CTRL + Print"
                (lua ''hl.dsp.exec_cmd("grim - | wl-copy -t image/png")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + 4"
                (lua ''
                  hl.dsp.exec_cmd("wayfreeze --hide-cursor --after-freeze-cmd 'GEOM=$(slurp -d) || { pkill -x wayfreeze; exit; }; grim -g \"$GEOM\" - | wl-copy -t image/png; pkill -x wayfreeze'")
                '')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + 5"
                (lua ''
                  hl.dsp.exec_cmd("grim -g \"$(hyprctl activewindow -j | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')\" - | wl-copy -t image/png")
                '')
              ];
            }
            {
              _args = [
                "ALT + Print"
                (lua ''
                  hl.dsp.exec_cmd("grim -g \"$(hyprctl activewindow -j | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')\" - | wl-copy -t image/png")
                '')
              ];
            }

            # Quit / Power (Niri Shift+E, Ctrl+Alt+Delete, Shift+P)
            {
              _args = [
                "${mainMod} + SHIFT + E"
                (lua "hl.dsp.exit()")
              ];
            }
            {
              _args = [
                "CTRL + ALT + Delete"
                (lua "hl.dsp.exit()")
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + P"
                (lua ''hl.dsp.dpms("off")'')
              ];
            }
          ]
          ++ (
            # Idiomatic Nix list generation for Workspaces 1-10
            builtins.concatLists (
              builtins.genList (
                i:
                let
                  workspace = i + 1;
                  key = if workspace == 10 then "0" else toString workspace;
                in
                [
                  {
                    _args = [
                      "${mainMod} + ${key}"
                      (lua "hl.dsp.focus({ workspace = ${toString workspace} })")
                    ];
                  }
                  {
                    _args = [
                      "${mainMod} + CTRL + ${key}"
                      (lua "hl.dsp.window.move({ workspace = ${toString workspace} })")
                    ];
                  }
                ]
              ) 10
            )
          );

          # ---- WINDOWS AND WORKSPACES ----
          window_rule = [
            {
              name = "suppress-maximize-events";
              match = {
                class = ".*";
              };
              suppress_event = "maximize";
            }
            {
              name = "fix-xwayland-drags";
              match = {
                class = "^$";
                title = "^$";
                xwayland = true;
                float = true;
                fullscreen = false;
                pin = false;
              };
              no_focus = true;
            }
            {
              name = "move-hyprland-run";
              match = {
                class = "hyprland-run";
              };
              move = "20 monitor_h-120";
              float = true;
            }
          ];

          # layer_rule = [
          #   { match = { namespace = "waybar"; }; blur = true; }
          #   { match = { namespace = "notifications"; }; blur = true; ignore_alpha = 0.5; }
          #   { match = { namespace = "swayosd"; }; blur = true; }
          #   { match = { namespace = "launcher"; }; blur = true; ignore_alpha = 0.5; }
          # ];
        };
      };
    };
}

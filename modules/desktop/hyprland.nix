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

          # ---- Animations ----
          curve = [
            {
              _args = [
                "easeOutQuint"
                {
                  type = "bezier";
                  points = [
                    [
                      0.23
                      1
                    ]
                    [
                      0.32
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "easeInOutCubic"
                {
                  type = "bezier";
                  points = [
                    [
                      0.65
                      0.05
                    ]
                    [
                      0.36
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "linear"
                {
                  type = "bezier";
                  points = [
                    [
                      0
                      0
                    ]
                    [
                      1
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "almostLinear"
                {
                  type = "bezier";
                  points = [
                    [
                      0.5
                      0.5
                    ]
                    [
                      0.75
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "quick"
                {
                  type = "bezier";
                  points = [
                    [
                      0.15
                      0
                    ]
                    [
                      0.1
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "easy"
                {
                  type = "spring";
                  mass = 1;
                  stiffness = 71.2633;
                  dampening = 15.8273644;
                }
              ];
            }
          ];

          animation = [
            {
              leaf = "global";
              enabled = true;
              speed = 10;
              bezier = "default";
            }
            {
              leaf = "border";
              enabled = true;
              speed = 5.39;
              bezier = "easeOutQuint";
            }
            {
              leaf = "windows";
              enabled = true;
              speed = 4.79;
              spring = "easy";
            }
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 4.1;
              spring = "easy";
              style = "popin 87%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 1.49;
              bezier = "linear";
              style = "popin 87%";
            }
            {
              leaf = "fadeIn";
              enabled = true;
              speed = 1.73;
              bezier = "almostLinear";
            }
            {
              leaf = "fadeOut";
              enabled = true;
              speed = 1.46;
              bezier = "almostLinear";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 3.03;
              bezier = "quick";
            }
            {
              leaf = "layers";
              enabled = true;
              speed = 3.81;
              bezier = "easeOutQuint";
            }
            {
              leaf = "layersIn";
              enabled = true;
              speed = 4;
              bezier = "easeOutQuint";
              style = "fade";
            }
            {
              leaf = "layersOut";
              enabled = true;
              speed = 1.5;
              bezier = "linear";
              style = "fade";
            }
            {
              leaf = "fadeLayersIn";
              enabled = true;
              speed = 1.79;
              bezier = "almostLinear";
            }
            {
              leaf = "fadeLayersOut";
              enabled = true;
              speed = 1.39;
              bezier = "almostLinear";
            }
            {
              leaf = "workspaces";
              enabled = true;
              speed = 1.94;
              bezier = "almostLinear";
              style = "fade";
            }
            {
              leaf = "workspacesIn";
              enabled = true;
              speed = 1.21;
              bezier = "almostLinear";
              style = "fade";
            }
            {
              leaf = "workspacesOut";
              enabled = true;
              speed = 1.94;
              bezier = "almostLinear";
              style = "fade";
            }
            {
              leaf = "zoomFactor";
              enabled = true;
              speed = 7;
              bezier = "quick";
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
          bind = [
            # Core App Launching & State
            {
              _args = [
                "${mainMod} + Q"
                (lua "hl.dsp.exec_cmd('${terminal}')")
              ];
            }
            {
              _args = [
                "${mainMod} + C"
                (lua "hl.dsp.window.close()")
              ];
            }
            {
              _args = [
                "${mainMod} + M"
                (lua ''hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")'')
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
                "${mainMod} + R"
                (lua "hl.dsp.exec_cmd('${menu}')")
              ];
            }
            {
              _args = [
                "${mainMod} + P"
                (lua "hl.dsp.window.pseudo()")
              ];
            }

            # Window Sizing & Screen States (Niri 1:1)
            {
              _args = [
                "${mainMod} + F"
                (lua ''hl.dsp.window.fullscreen({ action = "toggle" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + F"
                (lua ''hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + V"
                (lua ''hl.dsp.window.float({ action = "toggle" })'')
              ];
            }

            # Column Manipulation (Niri Consume/Expel style)
            {
              _args = [
                "${mainMod} + comma"
                (lua ''hl.dsp.layout("togglesplit")'')
              ];
            }
            {
              _args = [
                "${mainMod} + period"
                (lua ''hl.dsp.window.float({ action = "toggle" })'')
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

            # Move Windows (Arrows)
            {
              _args = [
                "${mainMod} + SHIFT + left"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + right"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + up"
                (lua ''hl.dsp.window.move({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + down"
                (lua ''hl.dsp.window.move({ direction = "down" })'')
              ];
            }

            # Move Windows (Vim Keys)
            {
              _args = [
                "${mainMod} + SHIFT + H"
                (lua ''hl.dsp.window.move({ direction = "left" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + L"
                (lua ''hl.dsp.window.move({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + K"
                (lua ''hl.dsp.window.move({ direction = "up" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + J"
                (lua ''hl.dsp.window.move({ direction = "down" })'')
              ];
            }

            # Resize Columns (Niri Minus/Equal keys)
            {
              _args = [
                "${mainMod} + minus"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive -5% 0")'')
              ];
            }
            {
              _args = [
                "${mainMod} + equal"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive 5% 0")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + minus"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 -5%")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + equal"
                (lua ''hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 5%")'')
              ];
            }

            # Monitor Focus & Move (Niri Brackets)
            {
              _args = [
                "${mainMod} + bracketleft"
                (lua ''hl.dsp.focus({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + bracketright"
                (lua ''hl.dsp.focus({ monitor = "r" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + bracketleft"
                (lua ''hl.dsp.window.move({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + bracketright"
                (lua ''hl.dsp.window.move({ monitor = "r" })'')
              ];
            }

            # Lateral Workspace / Column Scrolling (Niri PageUp/Down)
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
                "${mainMod} + SHIFT + Page_Down"
                (lua ''hl.dsp.window.move({ workspace = "m+1" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + Page_Up"
                (lua ''hl.dsp.window.move({ workspace = "m-1" })'')
              ];
            }

            # Niri Mouse Wheel behavior (Scrolls columns laterally instead of workspaces)
            {
              _args = [
                "${mainMod} + mouse_down"
                (lua ''hl.dsp.focus({ direction = "right" })'')
              ];
            }
            {
              _args = [
                "${mainMod} + mouse_up"
                (lua ''hl.dsp.focus({ direction = "left" })'')
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

            # Screenshots
            {
              _args = [
                "${mainMod} + S"
                (lua ''hl.dsp.exec_cmd("grim - | wl-copy")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + S"
                (lua ''
                  hl.dsp.exec_cmd("wayfreeze --hide-cursor --after-freeze-cmd 'GEOM=$(slurp -d) || { pkill -x wayfreeze; exit; }; grim -g \"$GEOM\" - | wl-copy -t image/png; pkill -x wayfreeze'")
                '')
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
                      "${mainMod} + SHIFT + ${key}"
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

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

            # Lets direction-based focus/move cross monitor edges on their own,
            # in addition to the explicit move-to-monitor binds below.
            binds = {
              window_direction_monitor_fallback = true;
            };

            misc = {
              force_default_wallpaper = -1;
              disable_hyprland_logo = false;

              # niri tracks the pointer 1:1 while dragging or resizing, with no
              # animation catching up behind it. Both already default to false;
              # they are pinned so the animation set stays a faithful match even
              # if those defaults change.
              animate_manual_resizes = false;
              animate_mouse_windowdragging = false;
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
          # An exact transcription of niri's animation defaults, since niri is
          # the reference for how this machine should feel. Sources: niri's own
          # wiki (Configuration: Animations, plus the example shaders that
          # replicate its default open/close), and Hyprland's spring
          # implementation in hyprutils.
          #
          # niri's springs give a damping *ratio*, while Hyprland's `dampening`
          # is the raw damping coefficient, so c = 2 * ratio * sqrt(mass *
          # stiffness). niri hardcodes spring mass to 1, which Hyprland also
          # accepts, so the physics transfer exactly:
          #
          #   niri                                    stiffness  ratio  -> dampening
          #   window-movement, -resize, view movement  800        1.0     56.5685425
          #   workspace-switch                        1000        1.0     63.2455532
          #
          # overview-open-close has no leaf to map onto: Hyprland has no overview,
          # and it cannot gain one here. Every overview plugin renders by hooking
          # CHyprRenderer::renderWorkspace, and Hyprland's function hooking is
          # guarded to x86_64 (`#if !defined(__x86_64__) return false;` in
          # src/plugins/HookSystem.cpp), so on this aarch64 machine hook
          # installation always fails.
          #
          # niri's other two animations are easings, both 150ms:
          #
          #   window-open   ease-out-expo, scaling 50% -> 100% while fading in
          #   window-close  ease-out-quad, scaling 100% -> 80% while fading out
          #
          # The scale figures come from niri's default_open/default_close example
          # shaders, which are documented as equivalent to its built-in
          # animations, so `popin` mirrors them rather than being guesswork.
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
            # niri implements the true easing functions, Hyprland only cubic
            # beziers. ease-out-quad — 1-(1-t)^2 — happens to have an exact
            # bezier form: control points (1/3, 2/3) and (2/3, 1) make x(s) = s
            # and y(s) = 2s - s^2, reproducing it to floating-point precision.
            {
              _args = [
                "easeOutQuad"
                {
                  type = "bezier";
                  points = [
                    [
                      0.3333333
                      0.6666667
                    ]
                    [
                      0.6666667
                      1
                    ]
                  ];
                }
              ];
            }
            # ease-out-expo — 1-2^(-10t) — is transcendental, so no cubic bezier
            # is exact. These points are a minimax fit (max error 0.0067 of full
            # travel, vs 0.0120 for the usual easings.net approximation) and put
            # the initial slope at 6.855 against the true 10*ln2 = 6.931.
            {
              _args = [
                "easeOutExpo"
                {
                  type = "bezier";
                  points = [
                    [
                      0.1402
                      0.9608
                    ]
                    [
                      0.2998
                      1
                    ]
                  ];
                }
              ];
            }
          ];

          # `speed` is in deciseconds (1 = 100ms). Hyprland ignores it entirely
          # for spring curves — hyprutils drives those from the physics alone —
          # so the values on the spring leaves below are descriptive only,
          # roughly the settling time each spring works out to.
          animation = [
            # Catch-all for any leaf not named below, at niri's general tempo.
            {
              leaf = "global";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
            }

            # niri's window-movement, window-resize and horizontal-view-movement
            # all share one spring, and Hyprland's windowsMove covers the same
            # ground. It is spelled out rather than left to inherit from windows
            # because under the scrolling layout it fires on every focus change,
            # making it the animation that decides how the session feels.
            {
              leaf = "windows";
              enabled = true;
              speed = 4.5;
              spring = "niriMovement";
            }
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 4.5;
              spring = "niriMovement";
            }

            # window-open / window-close. The fade leaves carry the same curve
            # and duration as the scale, because niri drives both from a single
            # animation progress value.
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutExpo";
              style = "popin 50%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 1.5;
              bezier = "easeOutQuad";
              style = "popin 80%";
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

            # workspace-switch. niri stacks workspaces vertically, hence a
            # vertical slide rather than Hyprland's default cross-fade.
            # workspacesIn/Out and the specialWorkspace family are left to
            # inherit this: niri has one workspace animation, not several.
            {
              leaf = "workspaces";
              enabled = true;
              speed = 4.1;
              spring = "niriWorkspace";
              style = "slidevert";
            }

            # Hyprland's render zoom, which niri has no equivalent for. Kept on
            # the movement spring so that if the zoom is ever used it moves like
            # everything else.
            {
              leaf = "zoomFactor";
              enabled = true;
              speed = 4.5;
              spring = "niriMovement";
            }

            # Everything below has no niri counterpart, and niri does not animate
            # any of it, so neither do we. Notably: its focus ring recolours
            # instantly, and layer-shell surfaces just appear — quickshell's
            # surfaces animate themselves in QML (see quickshell/qml/osd/Osd.qml)
            # and a compositor fade on top of that read as a double animation.
            # borderangle, shadowangle and glowangle are already off by
            # Hyprland's own defaults, as is __internal_fadeCTM's tree entry.
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
            # niri opens popups, dims, switches and blanks without a transition.
            {
              leaf = "fadePopups";
              enabled = false;
            }
            {
              leaf = "fadePopupsIn";
              enabled = false;
            }
            {
              leaf = "fadePopupsOut";
              enabled = false;
            }
            {
              leaf = "fadeSwitch";
              enabled = false;
            }
            {
              leaf = "fadeDim";
              enabled = false;
            }
            {
              leaf = "fadeDpms";
              enabled = false;
            }
            {
              leaf = "fadeShadow";
              enabled = false;
            }
            {
              leaf = "fadeGlow";
              enabled = false;
            }
            {
              leaf = "monitorAdded";
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

            # ---- SCROLLING EXTRAS (no niri counterpart) ----
            # Hyprland's scrolling layout has a handful of layoutmsgs niri has no
            # action for. Each was checked against the running compositor: an
            # unknown one answers "no such layoutmsg for scrolling", and note that
            # arguments are NOT validated (layout("focus bogus") returns ok), so
            # only commands confirmed real are bound here.

            # Pull the active column fully into view when it is half off-screen.
            {
              _args = [
                "${mainMod} + Z"
                (lua ''hl.dsp.layout("fit_into_view")'')
              ];
            }
            # Pin the viewport, so opening or focusing windows stops scrolling it.
            {
              _args = [
                "${mainMod} + SHIFT + Z"
                (lua ''hl.dsp.layout("inhibit_scroll")'')
              ];
            }
            # Move this window out into a new column of its own.
            {
              _args = [
                "${mainMod} + SHIFT + period"
                (lua ''hl.dsp.layout("promote")'')
              ];
            }
            # Trade places with the column to either side, keeping focus.
            {
              _args = [
                "${mainMod} + SHIFT + bracketleft"
                (lua ''hl.dsp.layout("swapcol l")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + bracketright"
                (lua ''hl.dsp.layout("swapcol r")'')
              ];
            }
            # Fit modes: everything from here to the start/end of the tape, or
            # every column at once.
            {
              _args = [
                "${mainMod} + SHIFT + Home"
                (lua ''hl.dsp.layout("fit tobeg")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + End"
                (lua ''hl.dsp.layout("fit toend")'')
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + A"
                (lua ''hl.dsp.layout("fit all")'')
              ];
            }
            # Pan the tape a column at a time without moving focus — the thing
            # niri genuinely cannot do.
            {
              _args = [
                "${mainMod} + ALT + left"
                (lua ''hl.dsp.layout("move -col")'')
              ];
            }
            {
              _args = [
                "${mainMod} + ALT + right"
                (lua ''hl.dsp.layout("move +col")'')
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

            # Move Column to Monitor (Niri Mod+Shift+Ctrl+…). These are bound
            # even though binds.window_direction_monitor_fallback already carries
            # a column across an edge, because niri has them as explicit keys.
          ]
          ++
            lib.concatMap
              (m: [
                {
                  _args = [
                    "${mainMod} + SHIFT + CTRL + ${m.arrow}"
                    (lua ''hl.dsp.window.move({ monitor = "${m.dir}" })'')
                  ];
                }
                {
                  _args = [
                    "${mainMod} + SHIFT + CTRL + ${m.vim}"
                    (lua ''hl.dsp.window.move({ monitor = "${m.dir}" })'')
                  ];
                }
              ])
              [
                {
                  arrow = "left";
                  vim = "H";
                  dir = "l";
                }
                {
                  arrow = "down";
                  vim = "J";
                  dir = "d";
                }
                {
                  arrow = "up";
                  vim = "K";
                  dir = "u";
                }
                {
                  arrow = "right";
                  vim = "L";
                  dir = "r";
                }
              ]
          ++ [
            # Niri's Mod+Shift+V. Hyprland has no single action for this, so it
            # branches on the focused window: cycle_next only walks one set at a
            # time, and jumping to the set you are already in would go nowhere.
            {
              _args = [
                "${mainMod} + SHIFT + V"
                (lua ''
                  function()
                      local w = hl.get_active_window()
                      if w and w.floating then
                          hl.dispatch(hl.dsp.window.cycle_next({ tiled = true }))
                      else
                          hl.dispatch(hl.dsp.window.cycle_next({ floating = true }))
                      end
                  end
                '')
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

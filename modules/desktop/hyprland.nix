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
      menu = "qs ipc call launcher toggle";

      lua = lib.generators.mkLuaInline;
      hex = lib.removePrefix "#";
    in
    {
      wayland.windowManager.hyprland = {
        enable = true;
        configType = "lua";

        settings = {
          # A `_var` entry renders as a plain `local scroll = …` ahead of every
          # hl.* call in the generated config. The keybinds below call into it;
          # nothing here runs at load time.
          scroll = {
            _var = lua ''
              (function()
                  local M = {}

                  -- The scrolling layout has no "jump to the first/last column"
                  -- message, so walk a column at a time. With wrapping off (see
                  -- config.scrolling below) focus and swapcol clamp at the ends,
                  -- so stepping past the edge is a no-op; the window count
                  -- bounds the walk since columns can never outnumber windows.
                  local function walk(msg)
                      local ws = hl.get_active_workspace()
                      for _ = 1, (ws and ws.windows or 1) do
                          hl.dispatch(hl.dsp.layout(msg))
                      end
                  end

                  function M.focus_column_first()
                      walk("focus l")
                  end

                  function M.focus_column_last()
                      walk("focus r")
                  end

                  function M.move_column_to_first()
                      walk("swapcol l")
                  end

                  function M.move_column_to_last()
                      walk("swapcol r")
                  end

                  -- Resize by a fraction of the working area, which
                  -- hl.dsp.window.resize cannot do itself — it only takes
                  -- logical pixels. monitor.height is physical while the
                  -- reserved struts are already logical. Note Hyprland only
                  -- redistributes height in a column of two or more windows
                  -- (resizeTarget bails on one), so a lone window cannot be
                  -- made shorter.
                  function M.window_height_by(fraction)
                      local m = hl.get_active_monitor()
                      if not m then
                          return
                      end

                      local reserved = m.reserved or {}
                      local usable = m.height / (m.scale or 1) - (reserved.top or 0) - (reserved.bottom or 0)

                      hl.dispatch(hl.dsp.window.resize({
                          x = 0,
                          y = math.floor(usable * fraction + 0.5),
                          relative = true,
                      }))
                  end

                  return M
              end)()
            '';
          };

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

          on = [
            {
              _args = [
                "hyprland.start"
                # quickshell already runs as a home-manager user service bound to
                # the graphical session, so only the wallpaper daemon needs
                # starting here.
                (lua ''function () hl.exec_cmd("awww-daemon") end'')
              ];
            }
          ];

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

          config = {
            general = {
              gaps_in = 5;
              gaps_out = 20;
              border_size = 2;
              col = {
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

            scrolling = {
              fullscreen_on_one_column = true;

              # The Mod+Home/End walks rely on focus and swapcol clamping at the
              # ends of the tape to terminate. Hyprland defaults both to true.
              wrap_focus = false;
              wrap_swapcol = false;

              # What Mod+R cycles through. Hyprland's own default appends 1.0 to
              # the same three.
              explicit_column_widths = "0.333, 0.5, 0.667";
            };

            binds = {
              window_direction_monitor_fallback = true;
            };

            misc = {
              # Track the pointer 1:1 while dragging or resizing. Already
              # Hyprland's defaults; pinned in case those change.
              animate_manual_resizes = false;
              animate_mouse_windowdragging = false;
            };

            input = {
              kb_layout = "us";
              kb_options = "compose:ralt";
              follow_mouse = 1;
              sensitivity = 0;
              touchpad = {
                natural_scroll = false;
              };
            };
          };

          # Springs for movement, since `dampening` is the raw damping
          # coefficient — c = 2 * ratio * sqrt(mass * stiffness) — so with mass
          # hardcoded to 1 both leaves below come out critically damped
          # (ratio 1.0), settling without overshoot:
          #
          #   stiffness  ratio  -> dampening
          #   800        1.0     56.5685425
          #   1000       1.0     63.2455532
          curve = [
            {
              _args = [
                "movement"
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
                "workspaceSwitch"
                {
                  type = "spring";
                  mass = 1;
                  stiffness = 1000;
                  dampening = 63.2455532;
                }
              ];
            }
            # Hyprland only has cubic beziers. ease-out-quad — 1-(1-t)^2 — has
            # an exact bezier form: these control points make x(s) = s and
            # y(s) = 2s - s^2, matching to floating-point precision.
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
            # ease-out-expo — 1-2^(-10t) — is transcendental, so no bezier is
            # exact. A minimax fit: max error 0.0067 of full travel, initial
            # slope 6.855 against the true 10*ln2 = 6.931.
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

          # `speed` is in deciseconds (1 = 100ms). Hyprland ignores it for
          # spring curves, driving those from the physics alone, so the values
          # on the spring leaves below are descriptive only.
          animation = [
            {
              leaf = "global";
              enabled = true;
              speed = 2.5;
              bezier = "easeOutQuad";
            }

            # windowsMove is spelled out rather than left to inherit because
            # under the scrolling layout it fires on every focus change, making
            # it the animation that decides the feel.
            {
              leaf = "windows";
              enabled = true;
              speed = 4.5;
              spring = "movement";
            }
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 4.5;
              spring = "movement";
            }

            # The fade leaves carry the same curve as the scale so the two stay
            # in step.
            #
            # Open is stretched to ~350ms because a freshly-spawned client often
            # has not committed its first frame before a shorter animation ends,
            # so the window snaps from blank to drawn and reads as a stutter.
            # Close is stretched less — nothing races a render there.
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 3.5;
              bezier = "easeOutExpo";
              style = "popin 50%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 2.5;
              bezier = "easeOutQuad";
              style = "popin 80%";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 2.5;
              bezier = "easeOutQuad";
            }
            {
              leaf = "fadeIn";
              enabled = true;
              speed = 3.5;
              bezier = "easeOutExpo";
            }
            {
              leaf = "fadeOut";
              enabled = true;
              speed = 2.5;
              bezier = "easeOutQuad";
            }

            # Workspaces stack vertically, hence a slide rather than Hyprland's
            # default cross-fade. workspacesIn/Out and the specialWorkspace
            # family inherit this.
            {
              leaf = "workspaces";
              enabled = true;
              speed = 4.1;
              spring = "workspaceSwitch";
              style = "slidevert";
            }

            {
              leaf = "zoomFactor";
              enabled = true;
              speed = 4.5;
              spring = "movement";
            }

            # Nothing below is animated. Notably not the layer-shell surfaces:
            # quickshell animates its own in QML, and a compositor fade on top
            # read as a double animation. borderangle, shadowangle, glowangle
            # and __internal_fadeCTM are already off by Hyprland's defaults.
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

          bind = [
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
                "${mainMod} + Q"
                (lua "hl.dsp.window.close()")
              ];
            }
            # Mod is the Command key, so this mirrors macOS's ⌃⌘Q.
            {
              _args = [
                "${mainMod} + CTRL + Q"
                (lua "hl.dsp.exec_cmd('loginctl lock-session')")
              ];
            }

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

            # Hyprland rejects an unknown layoutmsg but does not validate its
            # arguments, so a typo in one of these fails silently.
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
            # Pan the tape a column at a time without moving focus.
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

            # No single message jumps to the ends of the tape, so these walk it
            # — see the `scroll` helper above.
            {
              _args = [
                "${mainMod} + Home"
                (lua "function() scroll.focus_column_first() end")
              ];
            }
            {
              _args = [
                "${mainMod} + End"
                (lua "function() scroll.focus_column_last() end")
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + Home"
                (lua "function() scroll.move_column_to_first() end")
              ];
            }
            {
              _args = [
                "${mainMod} + CTRL + End"
                (lua "function() scroll.move_column_to_last() end")
              ];
            }

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

            # Bound explicitly even though window_direction_monitor_fallback
            # already carries a column across an edge.
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
            # No single action cycles between the floating and tiled sets, so
            # branch on the focused window: cycle_next only walks one at a time.
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
                (lua "function() scroll.window_height_by(-0.1) end")
              ];
            }
            {
              _args = [
                "${mainMod} + SHIFT + equal"
                (lua "function() scroll.window_height_by(0.1) end")
              ];
            }

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

            # This MacBook has no Print key, so mirror macOS's ⌘⇧3/4/5 on Mod
            # (= Command). Print is kept for external keyboards.
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
          ++ (builtins.concatLists (
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
          ));

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
          ];

          # The namespace is a regex, so `^bar$` is anchored to keep out
          # bar-strut — the invisible full-width surface that reserves the top
          # edge (quickshell/qml/bar/Bar.qml); blurring it would blur the whole
          # strip rather than the two pills. ignore_alpha exempts the see-through
          # parts of surfaces larger than what they draw.
          layer_rule = [
            {
              name = "blur-bar";
              match = {
                namespace = "^bar$";
              };
              blur = true;
            }
            {
              name = "blur-notifications";
              match = {
                namespace = "notifications";
              };
              blur = true;
              ignore_alpha = 0.5;
            }
            {
              name = "blur-launcher";
              match = {
                namespace = "launcher";
              };
              blur = true;
              ignore_alpha = 0.5;
            }
            {
              name = "blur-osd";
              match = {
                namespace = "osd";
              };
              blur = true;
            }
          ];
        };
      };
    };
}

{
  # The look is CelestialCrafter's river rice (github.com/CelestialCrafter/dotfiles):
  # Rosé Pine Dawn, azuki font, borderless windows 14 px apart under a flat
  # Overlay bar of hearts. The behaviour is still this MacBook's macOS.
  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      zon = import ./_zon.nix { inherit lib; };
      inherit (zon) enum;

      kwim = pkgs.callPackage ./_kwim.nix { };
      kwm = pkgs.callPackage ./_kwm.nix { inherit kwim; };

      colour = hex: zon.colour hex "ff";

      setWallpaper = pkgs.writeShellApplication {
        name = "set-wallpaper";
        runtimeInputs = [
          pkgs.awww
          pkgs.coreutils
        ];
        text = ''
          for _ in $(seq 50); do
            awww query >/dev/null 2>&1 && break
            sleep 0.1
          done
          awww img ${../../../assets/botanical-shop.png} \
            --resize crop --crop-gravity center --filter Lanczos3 --transition-type none
        '';
      };

      # Volume, battery and the clock, the way the rice's yambar showed them;
      # kwm's bar reads it from stdin, ^#RRGGBBAA switching colour.
      statusCommand = pkgs.writeShellApplication {
        name = "river-status";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.wireplumber
        ];
        text = ''
          label() { printf '^#%sff%s^#! ' "${lib.removePrefix "#" palette.surface.neutral4}" "$1"; }
          while :; do
            volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
            case "$volume" in
              *MUTED*) vol="muted" ;;
              *) vol="$(printf '%s' "$volume" | awk '{ printf "%d", $2 * 100 + 0.5 }')%" ;;
            esac

            bat=""
            for supply in /sys/class/power_supply/*; do
              [ "$(cat "$supply/type" 2>/dev/null)" = Battery ] || continue
              bat="$(cat "$supply/capacity")%"
            done

            printf '%s%s  %s%s  %s\n' "$(label vol)" "$vol" "$(label bat)" "$bat" "$(date '+%m/%d/%Y %I:%M %p')"
            sleep 5
          done
        '';
      };

      # Mirrors macOS's Cmd+Shift+3/4 (whole screen / selected area), saving to
      # ~/Pictures/Screenshots and copying to the clipboard.
      screenshot = pkgs.writeShellApplication {
        name = "river-screenshot";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.grim
          pkgs.slurp
          pkgs.wl-clipboard
        ];
        text = ''
          geometry=""
          if [ "''${1:-screen}" = area ]; then
            geometry=$(slurp) || exit 0
          fi

          dir="$HOME/Pictures/Screenshots"
          mkdir -p "$dir"
          file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
          if [ -n "$geometry" ]; then
            grim -g "$geometry" "$file"
          else
            grim "$file"
          fi
          wl-copy < "$file"
        '';
      };

      # river runs this once it is up. The session units start first, as sway's
      # NixOS snippets did, and stop when river ends the session.
      init = pkgs.writeShellApplication {
        name = "river-init";
        runtimeInputs = [
          pkgs.dbus
          pkgs.systemd
          kwm
          statusCommand
        ];
        text = ''
          trap 'systemctl --user stop river-session.target' EXIT
          trap 'exit' TERM INT HUP

          dbus-update-activation-environment --systemd \
            WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP WLR_RENDERER
          systemctl --user start river-session.target

          river-status | kwm
        '';
      };

      terminal = "ghostty";
      menu = "fuzzel";

      # Tags 1-9 as on the rice, and its tenth, the special tag, behind S.
      tagNames = map toString (lib.range 1 9) ++ [ "s" ];
      tagMask = i: lib.foldl (mask: _: mask * 2) 1 (lib.range 1 i);

      key = mods: keysym: action: {
        inherit keysym;
        modifiers = lib.genAttrs mods (_: true);
        event.click.pressed = action;
      };
      spawn = argv: { spawn = { inherit argv; }; };
      sh = cmd: { spawn_shell = { inherit cmd; }; };

      # The media keys work locked too, as sway's --locked bindings did.
      media = lib.mapAttrsToList (keysym: cmd: key [ ] keysym (sh cmd)) {
        XF86AudioRaiseVolume = "swayosd-client --output-volume raise --max-volume 100";
        XF86AudioLowerVolume = "swayosd-client --output-volume lower";
        XF86AudioMute = "swayosd-client --output-volume mute-toggle";
        XF86AudioMicMute = "swayosd-client --input-volume mute-toggle";
        XF86MonBrightnessUp = "swayosd-client --device apple-panel-bl --brightness raise";
        XF86MonBrightnessDown = "swayosd-client --device apple-panel-bl --brightness lower";
        XF86AudioPlay = "playerctl play-pause";
        XF86AudioPause = "playerctl play-pause";
        XF86AudioStop = "playerctl stop";
        XF86AudioPrev = "playerctl previous";
        XF86AudioNext = "playerctl next";
      };

      bindings = [
        (key [ "mod4" ] "t" (spawn [ terminal ]))
        (key [ "mod4" ] "d" (spawn [ menu ]))
        (key [ "mod4" ] "q" (enum "close"))
        (key [ "mod4" "shift" ] "r" (enum "reload_config"))
        # Ctrl+Cmd+Q, as on macOS; swayidle answers the lock request.
        (key [ "mod4" "ctrl" ] "q" (spawn [ "loginctl" "lock-session" ]))
        (key [ "mod4" "shift" ] "e" {
          quit = {
            exit_session = true;
            hook = [
              "sh"
              "-c"
              "printf 'cancel\\nexit\\n' | fuzzel --dmenu --prompt 'exit river? ' | grep -qx exit"
            ];
          };
        })
        (key [ "mod4" "shift" ] "p" (spawn [ "wlopm" "--toggle" "*" ]))
        (key [ "mod4" ] "b" (enum "toggle_bar"))

        (key [ "mod4" ] "j" { focus_iter.direction = enum "forward"; })
        (key [ "mod4" ] "k" { focus_iter.direction = enum "reverse"; })
        (key [ "mod4" ] "Right" { focus_iter.direction = enum "forward"; })
        (key [ "mod4" ] "Down" { focus_iter.direction = enum "forward"; })
        (key [ "mod4" ] "Left" { focus_iter.direction = enum "reverse"; })
        (key [ "mod4" ] "Up" { focus_iter.direction = enum "reverse"; })
        (key [ "mod4" "ctrl" ] "j" { swap.direction = enum "forward"; })
        (key [ "mod4" "ctrl" ] "k" { swap.direction = enum "reverse"; })
        (key [ "mod4" "ctrl" ] "Right" { swap.direction = enum "forward"; })
        (key [ "mod4" "ctrl" ] "Down" { swap.direction = enum "forward"; })
        (key [ "mod4" "ctrl" ] "Left" { swap.direction = enum "reverse"; })
        (key [ "mod4" "ctrl" ] "Up" { swap.direction = enum "reverse"; })
        (key [ "mod4" ] "Return" { zoom.swap = true; })
        (key [ "mod4" ] "h" { modify_mfact.change.step = -0.05; })
        (key [ "mod4" ] "l" { modify_mfact.change.step = 0.05; })

        (key [ "mod4" ] "f" { toggle_fullscreen.in_window = false; })
        (key [ "mod4" ] "v" (enum "toggle_floating"))
        (key [ "mod4" ] "w" { switch_layout.layout = enum "monocle"; })
        (key [ "mod4" ] "e" { switch_layout.layout = enum "tile"; })

        (key [ "mod4" ] "Tab" (enum "switch_to_previous_tag"))
        (key [ "mod4" ] "Page_Up" { set_output_tag.tag.occupied = enum "reverse"; })
        (key [ "mod4" ] "Page_Down" { set_output_tag.tag.occupied = enum "forward"; })
        (key [ "mod4" ] "0" { set_output_tag.tag.tag = tagMask 9 - 1; })

        (key [ "mod4" "shift" ] "3" (spawn [ "river-screenshot" "screen" ]))
        (key [ "mod4" "shift" ] "4" (spawn [ "river-screenshot" "area" ]))
        (key [ ] "Print" (spawn [ "river-screenshot" "area" ]))

        # F6, the moon key: Do Not Disturb as on macOS (see idle.nix).
        (key [ ] "XF86Sleep" (spawn [ "makoctl" "mode" "-t" "do-not-disturb" ]))
      ]
      ++ lib.concatLists (
        lib.imap0 (i: name: [
          (key [ "mod4" ] name { set_output_tag.tag.tag = tagMask i; })
          (key [ "mod4" "ctrl" ] name { set_window_tag.tag.tag = tagMask i; })
          (key [ "mod4" "shift" "ctrl" ] name { toggle_output_tag.mask = tagMask i; })
        ]) tagNames
      )
      ++ media
      ++ map (b: b // { mode = "lock"; }) media;

      kwmConfig = {
        background = null;
        xcursor_theme = {
          name = "WhiteSur-cursors";
          size = 24;
        };

        # As tall as the rice's 42 px yambar, which also clears the 32 pt notch.
        bar = {
          position = enum "top";
          font = "azuki_font:size=15";
          height = 42;
          scheme = {
            normal = {
              fg = colour palette.surface.text;
              bg = colour palette.surface.panel;
            };
            select = {
              fg = colour palette.ui.accent;
              bg = colour palette.surface.panel;
            };
          };
          tags = {
            tags = lib.replicate 9 "♡" ++ [ "♫" ];
            click.middle = null;
          };
          mode = null;
          layout = null;
          title.click.left.zoom.swap = false;
          status = {
            data = enum "stdin";
            click.middle = null;
          };
          override_colors = [
            {
              area = enum "title";
              scheme.select = {
                fg = colour palette.surface.text;
                bg = colour palette.surface.panel;
              };
            }
          ];
        };

        sloppy_focus = true;
        cursor_warp = enum "on_focus_changed";
        default_window_decoration = enum "ssd";

        border = {
          width = 0;
          color = {
            focus = colour palette.ui.accent;
            unfocus = colour palette.surface.neutral2;
            swallowing = colour palette.hue.aqua;
          };
        };

        default_layout = enum "tile";
        layout = {
          tile = {
            nmaster = 1;
            mfact = 0.55;
            inner_gap = 14;
            outer_gap = 14;
            master_location = enum "left";
          };
          monocle.gap = 14;
        };

        bindings = {
          # Key repeat as on macOS here: HIDInitialKeyRepeat 166 ms, HIDKeyRepeat 33 ms.
          repeat_info = {
            rate = 30;
            delay = 167;
          };
          key = bindings;
          pointer = [
            {
              button = enum "left";
              modifiers.mod4 = true;
              event.pressed = enum "pointer_move";
            }
            {
              button = enum "right";
              modifiers.mod4 = true;
              event.pressed = enum "pointer_resize";
            }
            {
              button = enum "middle";
              modifiers.mod4 = true;
              event.pressed = enum "toggle_floating";
            }
          ];
        };

        window_rules = [
          {
            app_id = {
              str = "";
              match_null = true;
            };
            floating = true;
          }
          {
            title.str = "Picture-in-Picture";
            floating = true;
          }
          {
            app_id.str = "xdg-desktop-portal-gtk";
            floating = true;
          }
          {
            app_id.str = "com.mitchellh.ghostty";
            is_terminal = true;
          }
        ];
      };

      # The trackpad's macOS acceleration, rebuilt from its IORegistry curves.
      macosAccel = import ./_macos-accel.nix { };

      kwimConfig = {
        input_device_rules = [
          {
            repeat_info = {
              rate = 30;
              delay = 167;
            };
          }
        ];

        # macOS trackpad behaviour, from this machine's preferences: tap to
        # click, two-finger click/tap for secondary, no tap-and-drag, three-
        # finger drag, natural scrolling, and the IORegistry's acceleration
        # curves for pointer and scroll at their default speeds.
        libinput_device_rules = [
          {
            name.str = "Apple MTP multi-touch";
            tap = enum "enabled";
            tap_button_map = enum "lrm";
            click_method = enum "clickfinger";
            clickfinger_button_map = enum "lrm";
            drag = enum "disabled";
            three_finger_drag = enum "enabled_3fg";
            natural_scroll = enum "enabled";
            middle_button_emulation = enum "disabled";
            disable_while_typing = enum "enabled";
            disable_while_trackpointing = enum "enabled";
            accel_profile = enum "custom";
            accel_custom = {
              motion = macosAccel.pointer;
              scroll = macosAccel.scroll;
            };
          }
        ];

        xkb_keyboard_rules = [ { keymap.options.options = "compose:ralt"; } ];
      };
    in
    {
      packages = [
        kwm
        kwim
        pkgs.fuzzel
        pkgs.brightnessctl
        pkgs.playerctl
        pkgs.wireplumber
        pkgs.wlopm
        screenshot
      ];

      systemd.targets.river-session = {
        description = "river session";
        documentation = [ "man:systemd.special(7)" ];
        bindsTo = [ "graphical-session.target" ];
        wants = [ "graphical-session-pre.target" ];
        after = [ "graphical-session-pre.target" ];
      };

      # The wallpaper as awww had it: filling the screen, cropped about the
      # centre and scaled with Lanczos3. The image is set once the daemon
      # answers, and again whenever the daemon restarts.
      systemd.services.awww = {
        description = "Wallpaper";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe' pkgs.awww "awww-daemon";
          ExecStartPost = lib.getExe setWallpaper;
          Restart = "on-failure";
        };
      };

      # ProMotion's top fixed rate (VRR is not in the kernel yet), at the
      # integer 2x macOS uses for its default 1512x982.
      systemd.services.kanshi = {
        description = "Output configuration";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe pkgs.kanshi;
          Restart = "on-failure";
        };
      };

      xdg.config.files = {
        "river/init".source = lib.getExe init;
        "kwm/config.zon".text = zon.render kwmConfig;
        "kwim/config.zon".text = zon.render kwimConfig;
        "kanshi/config".text = ''
          profile {
            output eDP-1 mode 3024x1964@120Hz scale 2
          }
        '';
      };
    };
}

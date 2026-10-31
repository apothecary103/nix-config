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
      bare = lib.removePrefix "#";

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

      # Mirrors macOS's Cmd+Shift+3/4/5: the whole screen, a region dragged on
      # a frozen screen (wayfreeze, so menus and video hold still), or that
      # region opened in satty to mark up. Never the cursor (grim leaves it
      # out). Each lands in ~/Pictures/Screenshots and on the clipboard, with a
      # notification showing it.
      screenshot = pkgs.writeShellApplication {
        name = "river-screenshot";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.grim
          pkgs.libnotify
          pkgs.procps
          pkgs.satty
          pkgs.slurp
          pkgs.wayfreeze
          pkgs.wl-clipboard
        ];
        text = ''
          mode=''${1:-screen}
          dir="$HOME/Pictures/Screenshots"
          mkdir -p "$dir"
          file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

          geometry=""
          if [ "$mode" != screen ]; then
            ready=$(mktemp -u)
            wayfreeze --hide-cursor --after-freeze-cmd "touch $ready" &
            freeze=$!
            trap 'kill $freeze 2>/dev/null || true; rm -f "$ready"' EXIT
            for _ in $(seq 50); do [ -e "$ready" ] && break; sleep 0.02; done
            geometry=$(slurp -d -w 2 \
              -b '#${bare palette.surface.text}33' \
              -c '#${bare palette.ui.accent}ff' \
              -s '#${bare palette.ui.accent}22') || exit 0
          fi

          if [ -n "$geometry" ]; then
            grim -g "$geometry" "$file"
          else
            grim "$file"
          fi
          if [ "$mode" = edit ]; then
            kill "$freeze" 2>/dev/null || true
            satty --filename "$file" --output-filename "$file" \
              --copy-command wl-copy --early-exit --actions-on-enter save-to-file,save-to-clipboard
          else
            wl-copy < "$file"
          fi
          notify-send -a Screenshot -i "$file" "Screenshot" "$(basename "$file")" || true
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
        ];
        text = ''
          trap 'systemctl --user stop river-session.target' EXIT
          trap 'exit' TERM INT HUP

          dbus-update-activation-environment --systemd \
            WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP WLR_RENDERER
          systemctl --user start river-session.target

          kwm
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
        XF86AudioRaiseVolume = "osd volume-up";
        XF86AudioLowerVolume = "osd volume-down";
        XF86AudioMute = "osd volume-mute";
        XF86AudioMicMute = "osd mic-mute";
        XF86MonBrightnessUp = "osd brightness-up";
        XF86MonBrightnessDown = "osd brightness-down";
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
        (key [ "mod4" "ctrl" ] "q" (spawn [
          "loginctl"
          "lock-session"
        ]))
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
        (key [ "mod4" "shift" ] "p" (spawn [
          "wlopm"
          "--toggle"
          "*"
        ]))
        (key [ "mod4" ] "b" (spawn [
            "qs"
            "ipc"
            "call"
            "bar"
            "toggle"
          ]))

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

        (key [ "mod4" "shift" ] "3" (spawn [
          "river-screenshot"
          "screen"
        ]))
        (key [ "mod4" "shift" ] "4" (spawn [
          "river-screenshot"
          "area"
        ]))
        (key [ "mod4" "shift" ] "5" (spawn [
          "river-screenshot"
          "edit"
        ]))
        (key [ ] "Print" (spawn [
          "river-screenshot"
          "area"
        ]))

        # F6, the moon key: Do Not Disturb as on macOS (see idle.nix).
        (key [ ] "XF86Sleep" (spawn [
          "makoctl"
          "mode"
          "-t"
          "do-not-disturb"
        ]))
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

        # Quickshell draws the bar (see quickshell/); kwm's own stays hidden,
        # but its ten tags are what the bar is told about.
        bar = {
          show_default = false;
          tags.tags = lib.replicate 9 "┻" ++ [ "┯" ];
          mode = null;
          layout = null;
          title = null;
          status = null;
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

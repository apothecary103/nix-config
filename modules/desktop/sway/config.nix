{
  flake.modules.nixos.base = {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # libadwaita apps read light/dark from the portal Settings backend, and
    # sway has no gnome-settings-daemon to answer it (see gtk.nix).
    xdg.portal.config.sway."org.freedesktop.impl.portal.Settings" = "gtk";
  };

  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      # Roles from the grouped palette (orchard's surface/hue attrsets).
      base = palette.surface.background;
      mantle = palette.surface.panel;
      fg = palette.surface.text;
      subtext = palette.surface.textDim;
      overlay = palette.surface.neutral3;
      surface0 = palette.surface.neutral0;
      surface1 = palette.surface.neutral1;
      blue = palette.hue.blue;
      red = palette.hue.red;
      bgHex = lib.removePrefix "#" base;

      # Plain text on purpose: swaybar renders whatever this prints, so the
      # bar needs no companion program such as i3status or waybar.
      statusCommand = pkgs.writeShellApplication {
        name = "sway-status";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.wireplumber
        ];
        text = ''
          while :; do
            volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
            vol=$(printf '%s' "$volume" | awk '{ printf "%d", $2 * 100 + 0.5 }')
            case "$volume" in
              *MUTED*) vol="muted" ;;
              *) vol="$vol%" ;;
            esac

            bat=""
            for supply in /sys/class/power_supply/*; do
              [ "$(cat "$supply/type" 2>/dev/null)" = Battery ] || continue
              bat="$(cat "$supply/capacity")% $(cat "$supply/status")"
            done

            printf 'vol %s  |  bat %s  |  %s\n' "$vol" "$bat" "$(date '+%a %d %b  %H:%M')"
            sleep 5
          done
        '';
      };

      # Mirrors macOS's Cmd+Shift+3/4 (whole screen / selected area), saving to
      # ~/Pictures/Screenshots and copying to the clipboard.
      screenshot = pkgs.writeShellApplication {
        name = "sway-screenshot";
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

      terminal = "ghostty";
      menu = "fuzzel";
      workspaces = map toString (lib.range 1 9);

      # The trackpad's macOS acceleration, rebuilt from its IORegistry curves.
      macosAccel = import ./_macos-accel.nix { };
    in
    {
      packages = [
        pkgs.fuzzel
        pkgs.brightnessctl
        pkgs.playerctl
        pkgs.wireplumber
        statusCommand
        screenshot
      ];

      xdg.config.files = {
        "sway/config".text = ''
          # NixOS's own snippets: exporting the session environment to D-Bus and
          # systemd, and starting sway-session.target. Portals and every user
          # unit bound to graphical-session.target depend on them.
          include /etc/sway/config.d/*

          set $mod Mod4
          set $term ${terminal}
          set $menu ${menu}

          # ProMotion's top fixed rate (VRR is not in the kernel yet), at the
          # integer 2x macOS uses for its default 1512x982. DCP takes 10-bit
          # scanout, which keeps P3 gradients from banding.
          output eDP-1 mode 3024x1964@120Hz scale 2 render_bit_depth 10
          output * bg ${base} solid_color

          # Key repeat as on macOS here: HIDInitialKeyRepeat 166 ms, HIDKeyRepeat 33 ms.
          input type:keyboard {
            xkb_options compose:ralt
            repeat_delay 167
            repeat_rate 30
          }

          # macOS trackpad behaviour, from this machine's preferences: tap to
          # click, two-finger click/tap for secondary, no tap-and-drag, three-
          # finger drag, natural scrolling, and the IORegistry's acceleration
          # curves for pointer and scroll at their default speeds.
          input type:touchpad {
            tap enabled
            tap_button_map lrm
            click_method clickfinger
            clickfinger_button_map lrm
            drag disabled
            three_finger_drag three_finger
            natural_scroll enabled
            middle_emulation disabled
            dwt enabled
            dwtp enabled
            accel_profile custom
            pointer_accel_custom ${macosAccel.pointer}
            scroll_accel_custom ${macosAccel.scroll}
          }

          # With three-finger drag on, macOS moves Spaces to four fingers, and a
          # thumb-and-three-finger pinch opens Launchpad.
          bindgesture swipe:4:left workspace next
          bindgesture swipe:4:right workspace prev
          bindgesture pinch:4:inward exec $menu
          seat * xcursor_theme WhiteSur-cursors 24

          default_border pixel 2
          default_floating_border pixel 2
          hide_edge_borders none

          client.focused          ${blue} ${blue} ${base} ${blue}
          client.focused_inactive ${surface0} ${surface0} ${subtext} ${surface0}
          client.unfocused        ${surface0} ${surface0} ${subtext} ${surface0}
          client.urgent           ${red} ${red} ${base} ${red}

          for_window [title="^Picture-in-Picture$"] floating enable
          # Fullscreen video keeps the display awake, as macOS does.
          for_window [all] inhibit_idle fullscreen

          bindsym $mod+t exec $term
          bindsym $mod+d exec $menu
          bindsym $mod+q kill
          bindsym $mod+Shift+r reload
          # Ctrl+Cmd+Q, as on macOS; swayidle answers the lock request.
          bindsym $mod+Ctrl+q exec loginctl lock-session
          bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit sway?' -B 'Exit' 'swaymsg exit'
          bindsym $mod+Shift+p exec swaymsg "output * power toggle"

          bindsym $mod+Left focus left
          bindsym $mod+Down focus down
          bindsym $mod+Up focus up
          bindsym $mod+Right focus right
          bindsym $mod+h focus left
          bindsym $mod+j focus down
          bindsym $mod+k focus up
          bindsym $mod+l focus right

          bindsym $mod+Ctrl+Left move left
          bindsym $mod+Ctrl+Down move down
          bindsym $mod+Ctrl+Up move up
          bindsym $mod+Ctrl+Right move right
          bindsym $mod+Ctrl+h move left
          bindsym $mod+Ctrl+j move down
          bindsym $mod+Ctrl+k move up
          bindsym $mod+Ctrl+l move right

          bindsym $mod+f fullscreen toggle
          bindsym $mod+v floating toggle
          bindsym $mod+Shift+v focus mode_toggle
          bindsym $mod+w layout toggle tabbed split
          bindsym $mod+e split toggle
          bindsym $mod+r mode "resize"

          mode "resize" {
            bindsym Left resize shrink width 10px
            bindsym Down resize grow height 10px
            bindsym Up resize shrink height 10px
            bindsym Right resize grow width 10px
            bindsym h resize shrink width 10px
            bindsym j resize grow height 10px
            bindsym k resize shrink height 10px
            bindsym l resize grow width 10px
            bindsym Return mode "default"
            bindsym Escape mode "default"
          }

          bindsym $mod+Page_Up workspace prev
          bindsym $mod+Page_Down workspace next
          ${lib.concatMapStrings (n: ''
            bindsym $mod+${n} workspace number ${n}
            bindsym $mod+Ctrl+${n} move container to workspace number ${n}
          '') workspaces}

          bindsym $mod+Shift+3 exec sway-screenshot screen
          bindsym $mod+Shift+4 exec sway-screenshot area

          bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
          bindsym --locked XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
          bindsym --locked XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
          bindsym --locked XF86AudioMicMute exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
          bindsym --locked XF86MonBrightnessUp exec brightnessctl set +5%
          bindsym --locked XF86MonBrightnessDown exec brightnessctl set 5%-
          bindsym --locked XF86AudioPlay exec playerctl play-pause
          bindsym --locked XF86AudioPause exec playerctl play-pause
          bindsym --locked XF86AudioStop exec playerctl stop
          bindsym --locked XF86AudioPrev exec playerctl previous
          bindsym --locked XF86AudioNext exec playerctl next

          # 37 px is the notch's height at scale 2 (appledrm.show_notch adds 74
          # rows), the same as the macOS menu bar, so nothing sits under it.
          bar {
            position top
            height 37
            font Maple Mono NF CN 11
            status_command ${lib.getExe statusCommand}
            colors {
              background ${mantle}
              statusline ${fg}
              separator ${overlay}
              focused_workspace ${blue} ${blue} ${base}
              active_workspace ${surface1} ${surface1} ${fg}
              inactive_workspace ${mantle} ${mantle} ${subtext}
              urgent_workspace ${red} ${red} ${base}
            }
          }
        '';

        "fuzzel/fuzzel.ini".text = ''
          [main]
          font=Maple Mono NF CN:size=12
          width=40
          lines=10

          [colors]
          background=${bgHex}ff
          text=${lib.removePrefix "#" fg}ff
          match=${lib.removePrefix "#" blue}ff
          selection=${lib.removePrefix "#" surface1}ff
          selection-text=${lib.removePrefix "#" fg}ff
          selection-match=${lib.removePrefix "#" blue}ff
          border=${lib.removePrefix "#" blue}ff

          [border]
          width=2
          radius=8
        '';
      };
    };
}

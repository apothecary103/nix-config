{
  # brightnessctl writes the backlight itself; its rules hand that to group video.
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      services.udev.packages = [ pkgs.brightnessctl ];
    };

  # The volume and brightness overlay macOS shows for the media keys, drawn by
  # the bar's eww (see river/bar.nix) in the bar's style: flat Overlay, azuki,
  # a rose level. It sits top right under the bar, where macOS puts it now,
  # and steps in sixteenths as macOS does. The river config binds the keys.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      osd = pkgs.writeShellApplication {
        name = "osd";
        runtimeInputs = [
          pkgs.brightnessctl
          pkgs.coreutils
          pkgs.eww
          pkgs.gawk
          pkgs.wireplumber
        ];
        text = ''
          sink=@DEFAULT_AUDIO_SINK@
          source=@DEFAULT_AUDIO_SOURCE@
          panel=apple-panel-bl

          # apple-panel-bl counts in nits and switches off at 2, so the
          # lowest step stays at 6.
          case "''${1:-}" in
            volume-up) wpctl set-mute "$sink" 0; wpctl set-volume -l 1.0 "$sink" 6.25%+ ;;
            volume-down) wpctl set-volume "$sink" 6.25%- ;;
            volume-mute) wpctl set-mute "$sink" toggle ;;
            mic-mute) wpctl set-mute "$source" toggle ;;
            brightness-up) brightnessctl -q -d "$panel" set 6.25%+ ;;
            brightness-down) brightnessctl -q -d "$panel" -n 6 set 6.25%- ;;
            *) echo "usage: osd volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down" >&2; exit 2 ;;
          esac

          level() { awk '{ printf "%d", $2 * 100 + 0.5 }'; }
          case "$1" in
            volume-*)
              state=$(wpctl get-volume "$sink")
              label=volume; value=$(level <<< "$state")
              [[ $state == *MUTED* ]] && label=muted ;;
            mic-*)
              state=$(wpctl get-volume "$source")
              label=microphone; value=$(level <<< "$state")
              [[ $state == *MUTED* ]] && label="microphone muted" ;;
            brightness-*)
              label=brightness
              value=$(brightnessctl -d "$panel" -m | cut -d, -f4 | tr -d %) ;;
          esac

          eww --no-daemonize update osd_label="$label" osd_value="$value"
          eww --no-daemonize open osd >/dev/null 2>&1 || true

          # Close 1.5 s after the last key, however many came in between.
          token="$XDG_RUNTIME_DIR/osd-token"
          stamp=$(date +%s%N)
          echo "$stamp" > "$token"
          (
            sleep 1.5
            if [ "$(cat "$token")" = "$stamp" ]; then eww --no-daemonize close osd; fi
          ) >/dev/null 2>&1 &
        '';
      };
    in
    {
      packages = [ osd ];

      xdg.config.files."eww/osd.yuck".text = ''
        (defvar osd_label "volume")
        (defvar osd_value 0)

        (defwindow osd
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "osd"
          :geometry (geometry :x "13px" :y "13px" :width "280px" :anchor "top right")
          (box :class {matches(osd_label, "muted$") ? "osd muted" : "osd"}
               :orientation "v" :space-evenly false
            (box :space-evenly false
              (label :class "osd-label" :halign "start" :hexpand true :text {osd_label})
              (label :class "osd-value" :halign "end" :text "''${osd_value}%"))
            (progress :class "osd-level" :orientation "h" :value {osd_value})))
      '';

      xdg.config.files."eww/osd.scss".text = ''
        .osd {
          padding: 14px 18px;
          background-color: ${palette.surface.panel};
          color: ${palette.surface.text};
          font-family: "azuki_font";
          font-size: 20px;
        }

        .osd-value {
          color: ${palette.surface.neutral4};
        }

        .osd-level {
          margin-top: 10px;
        }

        .osd-level trough {
          min-height: 6px;
          background-color: ${palette.surface.neutral1};
        }

        .osd-level progress {
          min-height: 6px;
          background-color: ${palette.ui.accent};
        }

        .osd.muted .osd-level progress {
          background-color: ${palette.surface.neutral4};
        }
      '';
    };
}

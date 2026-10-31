{
  # brightnessctl writes the backlight itself; its rules hand that to group video.
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      services.udev.packages = [ pkgs.brightnessctl ];
    };

  # The media keys: step volume and brightness in sixteenths as macOS does,
  # then show the level in the notch island (quickshell/qml/island). The river
  # config binds the keys.
  flake.modules.hjem.linux =
    { pkgs, ... }:
    let
      osd = pkgs.writeShellApplication {
        name = "osd";
        runtimeInputs = [
          pkgs.brightnessctl
          pkgs.coreutils
          pkgs.gawk
          pkgs.quickshell
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
            brightness-down) brightnessctl -q -d "$panel" --min-value=6 set 6.25%- ;;
            *) echo "usage: osd volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down" >&2; exit 2 ;;
          esac

          level() { awk '{ printf "%d", $2 * 100 + 0.5 }'; }
          case "$1" in
            volume-*)
              state=$(wpctl get-volume "$sink")
              kind=volume; label=volume; value=$(level <<< "$state")
              [[ $state == *MUTED* ]] && label=muted ;;
            mic-*)
              state=$(wpctl get-volume "$source")
              kind=microphone; label=microphone; value=$(level <<< "$state")
              [[ $state == *MUTED* ]] && label="microphone muted" ;;
            brightness-*)
              kind=brightness; label=brightness
              value=$(brightnessctl -d "$panel" -m | cut -d, -f4 | tr -d %) ;;
          esac

          qs ipc call island osd "$kind" "$value" "$label" >/dev/null 2>&1 || true
        '';
      };
    in
    {
      packages = [ osd ];
    };
}

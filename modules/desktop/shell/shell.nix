{ lib, ... }:
let
  # Lucide, the open icon set closest to SF Symbols: 2 px rounded strokes on
  # a 24 grid. Its glyphs are named after the icons, so the codepoints are
  # read from the font rather than copied in.
  lucideMap =
    pkgs:
    let
      python = pkgs.python3.withPackages (p: [ p.fonttools ]);
      json = pkgs.runCommandLocal "lucide-codepoints.json" { } ''
        ${python}/bin/python3 -I - ${pkgs.lucide}/share/fonts/truetype/Lucide.ttf > $out <<'EOF'
        import json, sys
        from fontTools.ttLib import TTFont
        cmap = TTFont(sys.argv[1]).getBestCmap()
        print(json.dumps({name: code for code, name in cmap.items()}))
        EOF
      '';
    in
    lib.mapAttrs (_: code: builtins.fromJSON ''"\u${lib.toLower (lib.toHexString code)}"'') (
      builtins.fromJSON (builtins.readFile json)
    );
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      fonts.packages = [ pkgs.lucide ];
    };

  # The desktop shell, in eww: a menubar flush with the notch, a control
  # centre and a calendar that drop from it, and the volume and brightness
  # overlay. Square throughout, on a 4 px grid, in Maple Mono with Lucide
  # icons, coloured by the matugen theme's Material roles.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      icon = lucideMap pkgs;
      m = palette.native;
      eww = lib.getExe pkgs.eww;

      # Until river blurs what is behind them, the materials stay nearly
      # opaque; with blur they drop to Material's translucent values.
      material = "0.88";

      script =
        name: runtimeInputs: text:
        lib.getExe (pkgs.writeShellApplication { inherit name runtimeInputs text; });

      # kwm's tags and focused window, every time kwm replaces its state file.
      tags = script "shell-tags" [ pkgs.coreutils pkgs.inotify-tools ] ''
        dir="$XDG_RUNTIME_DIR/kwm"
        until [ -d "$dir" ]; do sleep 0.2; done
        [ -f "$dir/state.json" ] && cat "$dir/state.json"
        inotifywait -mq -e moved_to --format %f "$dir" | while read -r file; do
          if [ "$file" = state.json ]; then cat "$dir/state.json"; fi
        done
      '';

      # The default sink whenever pipewire reports a change, reconnecting
      # when the server comes back.
      volume =
        script "shell-volume"
          [
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.pulseaudio
          ]
          ''
            emit() {
              local level muted
              level=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d %) || level=""
              muted=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{ print ($2 == "yes") ? "true" : "false" }') || muted=false
              printf '{"level":%s,"muted":%s}\n' "''${level:-0}" "''${muted:-false}"
            }
            while :; do
              emit
              pactl subscribe | grep --line-buffered -E "'change' on (sink|server)" | while read -r _; do
                emit
              done || true
              sleep 1
            done
          '';

      # The connection worth showing, whenever NetworkManager reports one.
      network =
        script "shell-network"
          [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.jq
            pkgs.networkmanager
          ]
          ''
            emit() {
              local enabled wired wifi strength ssid kind
              enabled=$(nmcli -t radio wifi)
              wired=$(nmcli -t -f TYPE,STATE device | grep -c '^ethernet:connected$' || true)
              wifi=$(nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null | grep '^\*' | head -1 || true)
              strength=$(cut -d: -f2 <<< "$wifi")
              ssid=$(cut -d: -f3- <<< "$wifi")
              if [ "$wired" -gt 0 ]; then kind=wired; elif [ -n "$wifi" ]; then kind=wifi; else kind=none; fi
              jq -cn --arg kind "$kind" --arg ssid "$ssid" --argjson strength "''${strength:-0}" \
                --argjson enabled "$([ "$enabled" = enabled ] && echo true || echo false)" \
                '{kind: $kind, ssid: $ssid, strength: $strength, enabled: $enabled}'
            }
            emit
            nmcli monitor | while read -r _; do emit; done
          '';

      # The playing track, as playerctl follows it.
      media = script "shell-media" [ pkgs.jq pkgs.playerctl ] ''
        playerctl -F metadata --format '{{status}}	{{title}}	{{artist}}' 2>/dev/null |
          jq -R --unbuffered -c 'split("\t") | {status: .[0], title: (.[1] // ""), artist: (.[2] // "")}'
      '';

      # Popovers: one open at a time, over a clear scrim that closes them on
      # any click outside. Content slides in with a revealer, and out before
      # the window closes, so the exit animates too.
      popover = script "shell-popover" [ pkgs.coreutils pkgs.eww ] ''
        want=''${1:-}
        open=$(eww active-windows 2>/dev/null | cut -d: -f1)
        close_all() {
          eww update control_open=false calendar_open=false
          sleep 0.15
          eww close control calendar scrim >/dev/null 2>&1 || true
        }
        if grep -qx "$want" <<< "$open" || [ -z "$want" ]; then
          close_all
          exit 0
        fi
        grep -qx scrim <<< "$open" && close_all
        eww open scrim
        eww open "$want"
        eww update "''${want}_open=true"
      '';

      # The control centre's switches.
      toggle =
        script "shell-toggle"
          [
            pkgs.bluez
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.mako
            pkgs.networkmanager
            pkgs.systemd
          ]
          ''
            wifi() { [ "$(nmcli radio wifi)" = enabled ]; }
            bluetooth() { bluetoothctl show | grep -q "Powered: yes"; }
            idle() { systemctl --user is-active -q swayidle; }
            case "''${1:-}" in
              wifi) if wifi; then nmcli radio wifi off; else nmcli radio wifi on; fi ;;
              bluetooth) if bluetooth; then bluetoothctl power off; else bluetoothctl power on; fi ;;
              dnd) makoctl mode -t do-not-disturb ;;
              awake) if idle; then systemctl --user stop swayidle; else systemctl --user start swayidle; fi ;;
            esac >/dev/null
          '';

      state =
        script "shell-state"
          [
            pkgs.bluez
            pkgs.brightnessctl
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.mako
            pkgs.systemd
          ]
          ''
            case "''${1:-}" in
              bluetooth) if bluetoothctl show | grep -q 'Powered: yes'; then echo true; else echo false; fi ;;
              dnd) if makoctl mode | grep -qx do-not-disturb; then echo true; else echo false; fi ;;
              awake) if systemctl --user is-active -q swayidle; then echo false; else echo true; fi ;;
              brightness) brightnessctl -d apple-panel-bl -m | cut -d, -f4 | tr -d % ;;
            esac
          '';

      clock = script "shell-clock" [ pkgs.coreutils ] ''
        date '+{"date":"%a %-d %b","time":"%H:%M"}'
      '';

      # The bar, once the daemon answers.
      open = script "shell-open" [ pkgs.eww ] ''
        until eww ping >/dev/null 2>&1; do sleep 0.1; done
        eww open bar
      '';

      session = script "shell-session" [ pkgs.systemd ] ''
        case "''${1:-}" in
          lock) loginctl lock-session ;;
          sleep) systemctl suspend ;;
          restart) systemctl reboot ;;
          shutdown) systemctl poweroff ;;
        esac
      '';

      numerals = [
        "一"
        "二"
        "三"
        "四"
        "五"
        "六"
        "七"
        "八"
        "九"
        "楽"
      ];
      numeral = lib.concatStringsSep ", " (map (n: ''"${n}"'') numerals);
    in
    {
      packages = [ pkgs.eww ];

      xdg.config.files."eww/eww.yuck".text = ''
        (deflisten kwm :initial '{"tags":[],"app_id":"","title":""}' "${tags}")
        (deflisten volume :initial '{"level":0,"muted":false}' "${volume}")
        (deflisten network :initial '{"kind":"none","ssid":"","strength":0,"enabled":true}' "${network}")
        (deflisten media :initial '{"status":"","title":"","artist":""}' "${media}")
        (defpoll clock :interval "10s" :initial '{"date":"","time":""}' "${clock}")

        (defvar control_open false)
        (defvar calendar_open false)
        (defpoll bluetooth :interval "3s" :initial "false" :run-while control_open "${state} bluetooth")
        (defpoll dnd :interval "3s" :initial "false" :run-while control_open "${state} dnd")
        (defpoll awake :interval "3s" :initial "false" :run-while control_open "${state} awake")
        (defpoll brightness :interval "1s" :initial "0" :run-while control_open "${state} brightness")

        (defvar numerals '[${numeral}]')

        (include "./bar.yuck")
        (include "./control.yuck")
        (include "./calendar.yuck")
        (include "./osd.yuck")
      '';

      xdg.config.files."eww/bar.yuck".text = ''
        ; The menubar: 32 tall like the notch, left and right halves either side
        ; of a 224-wide dead zone around it. Every target runs the full height,
        ; so the top edge of the screen is part of it (Fitts).
        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "32px" :anchor "top center")
          (centerbox :class "menubar"
            (box :class "half" :space-evenly false :halign "start"
              (eventbox :class "item logo" :onclick "${popover} control"
                (label :class "icon" :text "${icon.command}"))
              (box :class "tags" :space-evenly false
                (for tag in {kwm.tags}
                  (eventbox :class "tag ''${tag.focused ? 'focused' : tag.occupied ? 'occupied' : 'empty'}"
                            :visible {tag.focused || tag.occupied || tag.id <= 5}
                            :cursor "pointer"
                            :onclick "echo set_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                            :onrightclick "echo toggle_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                    (overlay
                      (label :class "numeral" :text {numerals[tag.id - 1]})
                      (box :class "underline" :valign "end" :halign "center")))))
              (label :class "title" :limit-width 48 :text {kwm.title ?: kwm.app_id}))
            (box :class "notch" :width 224)
            (box :class "half" :space-evenly false :halign "end"
              (eventbox :class "item media" :visible {media.status == "Playing"} :onclick "playerctl play-pause"
                (box :space-evenly false :spacing 8
                  (label :class "icon accent" :text "${icon.music}")
                  (label :class "secondary" :limit-width 28 :text {media.title})))
              (box :class "tray" (systray :icon-size 16 :spacing 8 :prepend-new true))
              (eventbox :class "item status ''${control_open ? 'open' : '''}" :onclick "${popover} control"
                        :onscroll "osd volume-{}"
                (box :space-evenly false :spacing 12
                  (label :class "icon ''${network.kind == 'none' ? 'off' : '''}"
                         :text {network.kind == "wired" ? "${icon.ethernet-port}" : network.kind == "wifi" ? (network.strength > 66 ? "${icon.wifi}" : network.strength > 33 ? "${icon.wifi-high}" : "${icon.wifi-low}") : "${icon.wifi-off}"})
                  (box :space-evenly false :spacing 4
                    (label :class "icon ''${volume.muted ? 'off' : '''}"
                           :text {volume.muted ? "${icon.volume-x}" : volume.level > 50 ? "${icon.volume-2}" : volume.level > 0 ? "${icon.volume-1}" : "${icon.volume}"})
                    (label :class "small" :text "''${volume.level}%"))
                  (box :space-evenly false :spacing 4 :visible {EWW_BATTERY != ""}
                    (label :class "icon ''${EWW_BATTERY['macsmc-battery'].capacity <= 20 && EWW_BATTERY['macsmc-battery'].status != 'Charging' ? 'low' : '''}"
                           :text {EWW_BATTERY['macsmc-battery'].status == "Charging" ? "${icon.battery-charging}" : EWW_BATTERY['macsmc-battery'].capacity > 80 ? "${icon.battery-full}" : EWW_BATTERY['macsmc-battery'].capacity > 40 ? "${icon.battery-medium}" : EWW_BATTERY['macsmc-battery'].capacity > 20 ? "${icon.battery-low}" : "${icon.battery-warning}"})
                    (label :class "small" :text "''${round(EWW_BATTERY['macsmc-battery'].capacity, 0)}%"))))
              (eventbox :class "item clock ''${calendar_open ? 'open' : '''}" :onclick "${popover} calendar"
                (box :space-evenly false :spacing 8
                  (label :class "secondary" :text {clock.date})
                  (label :class "time" :text {clock.time}))))))

        ; A clear surface under any open popover: a click outside closes it.
        (defwindow scrim
          :monitor 0
          :stacking "fg"
          :exclusive false
          :focusable "none"
          :namespace "scrim"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "100%" :anchor "top left")
          (eventbox :class "scrim" :onclick "${popover}"))
      '';

      xdg.config.files."eww/control.yuck".text = ''
        (defwidget tile [icon title state on action]
          (eventbox :class "tile ''${on ? 'on' : '''}" :onclick action :cursor "pointer"
            (box :class "tile-body" :space-evenly false :spacing 12
              (label :class "icon tile-icon" :text icon)
              (box :orientation "v" :space-evenly false :valign "center"
                (label :class "label" :halign "start" :text title)
                (label :class "small secondary" :halign "start" :limit-width 18 :text state)))))

        (defwidget slider [icon value onchange]
          (box :class "slider-row" :space-evenly false :spacing 12
            (label :class "icon" :text icon)
            (scale :class "slider" :hexpand true :min 0 :max 101 :value value :onchange onchange)
            (label :class "small secondary value" :text "''${round(value, 0)}")))

        (defwidget action [icon label command]
          (eventbox :class "action" :onclick command :cursor "pointer" :tooltip label
            (label :class "icon" :text icon)))

        (defwindow control
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "0px" :y "0px" :width "360px" :anchor "top right")
          (revealer :reveal control_open :transition "slidedown" :duration "200ms"
            (box :class "popover" :orientation "v" :space-evenly false
              (box :class "tiles" :orientation "v" :spacing 8 :space-evenly false
                (box :spacing 8 :homogeneous true
                  (tile :icon {network.enabled ? "${icon.wifi}" : "${icon.wifi-off}"} :title "Wi-Fi"
                        :state {network.enabled ? (network.ssid != "" ? network.ssid : "Not connected") : "Off"}
                        :on {network.enabled} :action "${toggle} wifi")
                  (tile :icon "${icon.bluetooth}" :title "Bluetooth" :state {bluetooth ? "On" : "Off"}
                        :on bluetooth :action "${toggle} bluetooth"))
                (box :spacing 8 :homogeneous true
                  (tile :icon "${icon.bell-off}" :title "Do Not Disturb" :state {dnd ? "On" : "Off"}
                        :on dnd :action "${toggle} dnd")
                  (tile :icon "${icon.coffee}" :title "Keep Awake" :state {awake ? "On" : "Off"}
                        :on awake :action "${toggle} awake")))
              (box :class "divider")
              (slider :icon "${icon.sun}" :value brightness :onchange "brightnessctl -q -d apple-panel-bl --min-value=6 set {}%")
              (slider :icon {volume.muted ? "${icon.volume-x}" : "${icon.volume-2}"} :value {volume.level}
                      :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%")
              (box :class "divider" :visible {media.title != ""})
              (box :class "media-row" :visible {media.title != ""} :space-evenly false :spacing 12
                (box :orientation "v" :hexpand true :space-evenly false :valign "center"
                  (label :class "label" :halign "start" :limit-width 30 :text {media.title})
                  (label :class "small secondary" :halign "start" :limit-width 34 :text {media.artist}))
                (action :icon "${icon.skip-back}" :label "Previous" :command "playerctl previous")
                (action :icon {media.status == "Playing" ? "${icon.pause}" : "${icon.play}"} :label "Play or pause" :command "playerctl play-pause")
                (action :icon "${icon.skip-forward}" :label "Next" :command "playerctl next"))
              (box :class "divider")
              (box :class "footer" :space-evenly false
                (label :class "small secondary" :hexpand true :halign "start"
                       :text "Battery ''${round(EWW_BATTERY['macsmc-battery'].capacity, 0)}%")
                (action :icon "${icon.lock}" :label "Lock" :command "${popover}; ${session} lock")
                (action :icon "${icon.moon}" :label "Sleep" :command "${popover}; ${session} sleep")
                (action :icon "${icon.rotate-ccw}" :label "Restart" :command "${session} restart")
                (action :icon "${icon.power}" :label "Shut Down" :command "${session} shutdown")))))
      '';

      xdg.config.files."eww/calendar.yuck".text = ''
        (defwindow calendar
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "0px" :y "0px" :width "312px" :anchor "top right")
          (revealer :reveal calendar_open :transition "slidedown" :duration "200ms"
            (box :class "popover" :orientation "v" :space-evenly false
              (label :class "heading" :halign "start" :text {clock.date})
              (calendar :class "month" :show-heading true :show-day-names true :show-week-numbers false))))
      '';

      xdg.config.files."eww/osd.yuck".text = ''
        (defvar osd_kind "volume")
        (defvar osd_value 0)
        (defvar osd_label "")
        (defvar osd_open false)

        ; Bottom centre, as macOS has it; not interactive.
        (defwindow osd
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "osd"
          :geometry (geometry :x "0" :y "96px" :width "280px" :anchor "bottom center")
          (revealer :reveal osd_open :transition "crossfade" :duration "150ms"
            (box :class "osd-card ''${osd_label == 'muted' || osd_label == 'microphone muted' ? 'muted' : '''}" :space-evenly false :spacing 12
              (label :class "icon osd-icon"
                     :text {osd_kind == "brightness" ? "${icon.sun}" : osd_kind == "microphone" ? (osd_label == "microphone muted" ? "${icon.mic-off}" : "${icon.mic}") : osd_label == "muted" ? "${icon.volume-x}" : osd_value > 50 ? "${icon.volume-2}" : "${icon.volume-1}"})
              (box :class "track" :valign "center" :space-evenly false
                (box :class "fill" :style "min-width: ''${osd_value * 1.6}px;"))
              (label :class "osd-value" :width 32 :halign "end" :text osd_value))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        // Material roles from the matugen theme (see theme.nix).
        $surface: ${m.surface};
        $container-lowest: ${m.surface_container_lowest};
        $container: ${m.surface_container};
        $container-high: ${m.surface_container_high};
        $container-highest: ${m.surface_container_highest};
        $on-surface: ${m.on_surface};
        $on-surface-variant: ${m.on_surface_variant};
        $outline: ${m.outline};
        $outline-variant: ${m.outline_variant};
        $primary: ${m.primary};
        $on-primary: ${m.on_primary};
        $primary-container: ${m.primary_container};
        $on-primary-container: ${m.on_primary_container};
        $error: ${m.error};
        $material: ${material};

        // Motion (Material 3): standard for state, emphasized in and out.
        $standard: cubic-bezier(0.2, 0, 0, 1);
        $fast: 100ms;

        // 4 px grid; Maple Mono throughout, Lucide for icons.
        * {
          all: unset;
          border-radius: 0;
          font-family: "Maple Mono NF CN";
          font-size: 13px;
          color: $on-surface;
        }

        .icon {
          font-family: "lucide";
          font-size: 16px;
        }
        .icon.off,
        .small.off {
          color: rgba($on-surface, 0.38);
        }
        .icon.low {
          color: $error;
        }
        .icon.accent {
          color: $primary;
        }
        .small {
          font-size: 11px;
          color: $on-surface-variant;
        }
        .secondary {
          color: $on-surface-variant;
        }

        // A state layer in the content colour: 8 % on hover, 10 % pressed.
        @mixin interactive {
          transition: background-color $fast $standard;
          &:hover {
            background-color: rgba($on-surface, 0.08);
          }
          &:active {
            background-color: rgba($on-surface, 0.1);
          }
        }

        .menubar {
          background-color: rgba($container-lowest, $material);
          border-bottom: 1px solid rgba($outline-variant, 0.5);
        }
        .half {
          padding: 0 4px;
        }
        // Eventboxes take no padding in GTK 3, so their content carries it.
        .item {
          min-height: 32px;
          @include interactive;
          > * {
            padding: 0 8px;
          }
        }
        .item.open {
          background-color: rgba($on-surface, 0.1);
        }
        .logo .icon {
          font-size: 15px;
        }

        .tags {
          margin: 0 8px;
        }
        .tag {
          min-width: 28px;
          min-height: 32px;
          @include interactive;
        }
        .tag .numeral {
          color: rgba($on-surface, 0.38);
          transition: color $fast $standard;
        }
        .tag.occupied .numeral {
          color: $on-surface;
        }
        .tag.focused .numeral {
          color: $on-surface;
          font-weight: bold;
        }
        .tag .underline {
          min-width: 16px;
          min-height: 2px;
          background-color: transparent;
          transition: background-color $fast $standard;
        }
        .tag.focused .underline {
          background-color: $primary;
        }

        .title {
          margin-left: 8px;
          color: $on-surface-variant;
        }
        .time {
          font-weight: bold;
        }
        .clock > * {
          padding-right: 12px;
        }
        .tray {
          padding: 0 8px;
        }

        .scrim {
          background-color: transparent;
        }

        // Popovers hang from the bar's hairline: no gap, no shadow, a 1 px
        // edge and tonal steps inside.
        .popover {
          background-color: rgba($container, $material);
          border: 1px solid rgba($outline-variant, 0.6);
          border-top: none;
          padding: 16px;
        }
        .divider {
          min-height: 1px;
          margin: 16px 0;
          background-color: rgba($outline-variant, 0.6);
        }
        .label {
          font-size: 13px;
        }
        .heading {
          font-size: 15px;
          font-weight: bold;
          margin-bottom: 12px;
        }

        .tile {
          background-color: rgba($container-highest, 0.6);
          min-height: 48px;
          @include interactive;
        }
        .tile-body {
          padding: 0 12px;
        }
        .tile.on {
          background-color: $primary-container;
        }
        .tile.on .tile-icon,
        .tile.on .label,
        .tile.on .small {
          color: $on-primary-container;
        }

        .slider-row {
          min-height: 32px;
          margin-top: 4px;
        }
        .slider .value {
          min-width: 28px;
        }
        scale trough {
          min-height: 4px;
          min-width: 100px;
          background-color: $container-highest;
        }
        scale highlight {
          background-color: $primary;
        }
        scale slider {
          min-width: 12px;
          min-height: 12px;
          margin: -4px 0;
          background-color: $primary;
          transition: box-shadow $fast $standard;
        }
        scale slider:hover {
          box-shadow: 0 0 0 4px rgba($primary, 0.16);
        }
        .value {
          min-width: 28px;
        }

        .media-row {
          min-height: 40px;
        }
        .action {
          min-width: 32px;
          min-height: 32px;
          @include interactive;
        }
        .action .icon {
          margin: 0 8px;
        }

        .month {
          padding: 4px 0;
        }
        calendar {
          font-size: 13px;
          background-color: transparent;
        }
        calendar.header {
          font-weight: bold;
        }
        calendar.button {
          color: $on-surface-variant;
        }
        calendar:selected {
          background-color: $primary;
          color: $on-primary;
        }
        calendar:indeterminate {
          color: rgba($on-surface, 0.38);
        }

        .osd-card {
          background-color: rgba($container, $material);
          border: 1px solid rgba($outline-variant, 0.6);
          padding: 0 16px;
          min-height: 56px;
        }
        .osd-icon {
          font-size: 20px;
        }
        .track {
          min-height: 4px;
          min-width: 160px;
          background-color: $container-highest;
        }
        .fill {
          min-height: 4px;
          background-color: $primary;
          transition: min-width $fast $standard;
        }
        .osd-card.muted .fill {
          background-color: rgba($on-surface, 0.38);
        }
        .osd-value {
          font-weight: bold;
        }
      '';

      systemd.services.eww = {
        description = "Desktop shell";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        # eww runs its scripts and click handlers through sh.
        path = [
          pkgs.bash
          pkgs.brightnessctl
          pkgs.coreutils
          pkgs.playerctl
          pkgs.wireplumber
        ];
        serviceConfig = {
          ExecStart = "${eww} daemon --no-daemonize";
          ExecStartPost = open;
          Restart = "on-failure";
        };
      };
    };
}

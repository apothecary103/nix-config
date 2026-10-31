{ lib, username, ... }:
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

  # The panel's notch, in logical pixels at the default 1512 x 982: about 185
  # wide and 32 deep. Asahi gives back the 37 rows beside it (show_notch=1),
  # which the bar fills.
  notch = {
    width = 185;
    height = 32;
  };
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      fonts.packages = [ pkgs.lucide ];
    };

  # The desktop shell, in eww, after Tail-R's xmonad rice: a strip of square
  # tiles along the top, each edged in the accent, with the notch framed as
  # one of them; a dashboard, a player and a power column that drop from it
  # under title bands; and the volume and brightness overlay. On a 4 px grid,
  # in Maple Mono with Lucide icons, coloured by the matugen theme's roles.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      icon = lucideMap pkgs;
      m = palette.native;
      eww = lib.getExe pkgs.eww;

      # Until river blurs what is behind them, surfaces stay nearly opaque.
      material = "0.94";

      strip = 37;
      tile = 29;
      frame = {
        width = notch.width + 12;
        height = strip - (strip - tile) / 2;
      };

      script =
        name: runtimeInputs: text:
        lib.getExe (pkgs.writeShellApplication { inherit name runtimeInputs text; });

      bat = "EWW_BATTERY['macsmc-battery']";

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

      bluetooth =
        script "shell-bluetooth"
          [
            pkgs.bluez
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.jq
          ]
          ''
            powered=false
            if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then powered=true; fi
            device=""
            if $powered; then
              device=$(bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3- || true)
            fi
            jq -cn --argjson powered "$powered" --arg device "$device" '{powered: $powered, device: $device}'
          '';

      # The playing track, as playerctl follows it, with its cover as a local
      # file: file:// art as is, remote art fetched once into the cache.
      media =
        script "shell-media"
          [
            pkgs.coreutils
            pkgs.curl
            pkgs.jq
            pkgs.playerctl
          ]
          ''
            cache="''${XDG_CACHE_HOME:-$HOME/.cache}/shell/art"
            mkdir -p "$cache"
            sep=$'\x1f'
            playerctl -F metadata --format "{{status}}$sep{{title}}$sep{{artist}}$sep{{mpris:artUrl}}$sep{{mpris:length}}$sep{{playerName}}" 2>/dev/null |
              while IFS=$sep read -r status title artist url length player; do
                case "$url" in
                  file://*) path=''${url#file://}; art=$(printf '%b' "''${path//%/\\x}") ;;
                  http://* | https://*)
                    art="$cache/$(printf %s "$url" | sha1sum | cut -c1-16)"
                    [ -s "$art" ] || curl -sfL --max-time 5 -o "$art" "$url" || art="" ;;
                  *) art="" ;;
                esac
                jq -nc --arg status "$status" --arg title "$title" --arg artist "$artist" --arg art "$art" \
                  --arg length "''${length:-0}" --arg player "$player" \
                  '{status: $status, title: $title, artist: $artist, art: $art, length: ($length | tonumber? // 0), player: $player}'
              done
          '';

      # Seconds into the track, while the player is open.
      position = script "shell-position" [ pkgs.playerctl ] ''
        playerctl position 2>/dev/null || echo 0
      '';

      repeat = script "shell-repeat" [ pkgs.playerctl ] ''
        if [ "$(playerctl loop 2>/dev/null)" = None ]; then playerctl loop Playlist; else playerctl loop None; fi
      '';

      clock = script "shell-clock" [ pkgs.coreutils ] ''
        date '+{"hour":"%H","minute":"%M","hour12":%-I,"weekday":"%A","date":"%-d, %B"}'
      '';

      brightness = script "shell-brightness" [ pkgs.brightnessctl pkgs.coreutils ] ''
        brightnessctl -d apple-panel-bl -m | cut -d, -f4 | tr -d %
      '';

      # Popovers: one open at a time, over a clear scrim that closes them on
      # any click outside. Content slides in with a revealer, and out before
      # the window closes, so the exit animates too.
      popovers = [
        "dashboard"
        "player"
        "power"
      ];
      popover = script "shell-popover" [ pkgs.coreutils pkgs.eww pkgs.gnugrep ] ''
        want=''${1:-}
        open=$(eww active-windows 2>/dev/null | cut -d: -f1)
        close_all() {
          eww update ${lib.concatMapStringsSep " " (p: "${p}_open=false") popovers} power_armed=""
          sleep 0.2
          eww close ${lib.concatStringsSep " " popovers} scrim >/dev/null 2>&1 || true
        }
        if [ -z "$want" ] || grep -qx "$want" <<< "$open"; then
          close_all
          exit 0
        fi
        grep -qx scrim <<< "$open" && close_all
        eww open scrim
        eww open "$want"
        eww update "''${want}_open=true"
      '';

      # The dashboard's switches.
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
            pkgs.gnugrep
            pkgs.mako
            pkgs.systemd
          ]
          ''
            case "''${1:-}" in
              dnd) if makoctl mode | grep -qx do-not-disturb; then echo true; else echo false; fi ;;
              awake) if systemctl --user is-active -q swayidle; then echo false; else echo true; fi ;;
            esac
          '';

      # Lock and sleep act at once; the rest ask for a second click within
      # three seconds, as the button turns to say.
      power =
        script "shell-power"
          [
            pkgs.coreutils
            pkgs.eww
            pkgs.systemd
          ]
          ''
            act() {
              ${popover}
              case "$1" in
                lock) loginctl lock-session ;;
                sleep) systemctl suspend ;;
                logout) loginctl terminate-session "$(loginctl show-user "$USER" -p Display --value)" ;;
                restart) systemctl reboot ;;
                shutdown) systemctl poweroff ;;
              esac
            }
            case "$1" in
              lock | sleep) act "$1" ;;
              *)
                if [ "$(eww get power_armed)" = "$1" ]; then
                  act "$1"
                else
                  eww update power_armed="$1"
                  (sleep 3; [ "$(eww get power_armed)" = "$1" ] && eww update power_armed="") >/dev/null 2>&1 &
                fi ;;
            esac
          '';

      # The bar, once the daemon answers.
      open = script "shell-open" [ pkgs.eww ] ''
        until eww ping >/dev/null 2>&1; do sleep 0.1; done
        eww open bar
      '';

      # Maple's Nerd Font hearts (Material Design Icons), filled, half and
      # outline, as Lucide draws only outlines.
      heart = {
        full = builtins.fromJSON ''"\udb80\uded1"'';
        half = builtins.fromJSON ''"\udb81\udede"'';
        empty = builtins.fromJSON ''"\udb80\uded5"'';
      };

      json = builtins.toJSON;
      clocks = json (map (h: icon."clock-${toString h}") (lib.range 1 12));
    in
    {
      packages = [ pkgs.eww ];

      xdg.config.files."eww/eww.yuck".text = ''
        (deflisten kwm :initial '{"tags":[],"app_id":"","title":""}' "${tags}")
        (deflisten volume :initial '{"level":0,"muted":false}' "${volume}")
        (deflisten network :initial '{"kind":"none","ssid":"","strength":0,"enabled":true}' "${network}")
        (deflisten media :initial '{"status":"","title":"","artist":"","art":"","length":0,"player":""}' "${media}")
        (defpoll bluetooth :interval "5s" :initial '{"powered":false,"device":""}' "${bluetooth}")
        (defpoll clock :interval "5s" :initial '{"hour":"","minute":"","hour12":12,"weekday":"","date":""}' "${clock}")
        (defpoll brightness :interval "5s" :initial "0" "${brightness}")

        ${lib.concatMapStringsSep "\n" (p: "(defvar ${p}_open false)") popovers}
        (defvar power_armed "")
        (defpoll position :interval "1s" :initial "0" :run-while player_open "${position}")
        (defpoll looping :interval "2s" :initial "None" :run-while player_open "playerctl loop 2>/dev/null || echo None")
        (defpoll dnd :interval "3s" :initial "false" :run-while dashboard_open "${state} dnd")
        (defpoll awake :interval "3s" :initial "false" :run-while dashboard_open "${state} awake")

        (defvar clocks '${clocks}')
        (defvar hearts '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]')

        (include "./bar.yuck")
        (include "./dashboard.yuck")
        (include "./player.yuck")
        (include "./power.yuck")
        (include "./osd.yuck")
      '';

      xdg.config.files."eww/bar.yuck".text = ''
        ; A ${toString strip}-tall strip, the height of the rows beside the notch,
        ; holding ${toString tile}-tall tiles. The notch gets a frame of its own,
        ; hung from the top edge and ending level with the tiles.
        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "${toString strip}px" :anchor "top center")
          (centerbox :class "strip"
            (box :class "group" :halign "start" :valign "start" :space-evenly false :spacing 6
              (eventbox :class "hit" :onclick "${popover} dashboard" :cursor "pointer" :tooltip "${username}"
                (box :class "tile avatar" :width ${toString tile} :height ${toString tile}))
              (box :class "tile workspaces" :width 150 :space-evenly false :halign "start"
                (box :hexpand true :halign "center" :space-evenly false :spacing 10
                  (for tag in {kwm.tags}
                    (eventbox :class "tag ''${tag.focused ? 'focused' : tag.occupied ? 'occupied' : 'empty'}"
                              :visible {tag.focused || tag.occupied || tag.id <= 5}
                              :cursor "pointer"
                              :tooltip "''${tag.id}"
                              :onclick "echo set_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                              :onrightclick "echo toggle_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                      (label :class "icon"
                             :text {tag.focused ? "${icon.cherry}" : tag.occupied ? "${icon.ghost}" : "${icon.dot}"})))))
              (box :class "tile title" :width 160 :space-evenly false
                (box :hexpand true :halign "center" :space-evenly false :spacing 8
                  (label :class "icon accent" :text "${icon.app-window}")
                  (label :class "value" :limit-width 14
                         :text {kwm.title != "" ? kwm.title : kwm.app_id != "" ? kwm.app_id : "desktop"})))
              (eventbox :class "hit" :cursor "pointer" :onclick "${popover} player"
                (box :class "tile music ''${player_open ? 'open' : '''}" :width 230 :height ${toString tile}
                (overlay
                  (box :class "cover"
                       :style {media.art != "" ? "background-image: url('" + media.art + "');" : ""})
                  (box :class "music-text" :orientation "v" :valign "center" :space-evenly false
                       :visible {media.title != ""}
                    (label :class "line" :halign "start" :limit-width 24 :text {media.title})
                    (label :class "line secondary" :halign "start" :limit-width 24 :text {media.artist}))
                  (box :class "music-text" :space-evenly false :spacing 8 :halign "center"
                       :visible {media.title == ""}
                    (label :class "icon faint" :text "${icon.music}")
                    (label :class "secondary" :text "nothing playing"))))))
            (box :class "notch" :width ${toString frame.width} :height ${toString frame.height} :valign "start")
            (box :class "group" :halign "end" :valign "start" :space-evenly false :spacing 6
              (eventbox :class "hit" :onclick "${popover} dashboard" :onscroll "osd volume-{}" :cursor "pointer"
                (box :class "tile inset" :height ${toString tile} :space-evenly false :spacing 14
                  (box :space-evenly false :spacing 6
                    (label :class "icon ''${bluetooth.powered ? 'accent' : 'faint'}"
                           :text {bluetooth.device != "" ? "${icon.bluetooth-connected}" : bluetooth.powered ? "${icon.bluetooth}" : "${icon.bluetooth-off}"})
                    (label :class {bluetooth.device == "" ? "value dim" : "value"} :limit-width 10
                           :text {bluetooth.device != "" ? bluetooth.device : bluetooth.powered ? "on" : "off"}))
                  (box :space-evenly false :spacing 6
                    (label :class "icon ''${network.kind == 'none' ? 'faint' : 'accent'}"
                           :text {network.kind == "wired" ? "${icon.ethernet-port}" : network.kind == "wifi" ? "${icon.wifi}" : "${icon.wifi-off}"})
                    (label :class "value ''${network.kind == 'none' ? 'dim' : '''}" :limit-width 12
                           :text {network.kind == "wifi" ? network.ssid : network.kind == "wired" ? "wired" : "offline"}))
                  (box :space-evenly false :spacing 6
                    (label :class "icon ''${volume.muted ? 'faint' : 'accent'}"
                           :text {volume.muted ? "${icon.volume-x}" : "${icon.volume-2}"})
                    (label :class "value" :text "''${volume.level}%"))
                  (box :space-evenly false :spacing 6
                    (label :class "icon accent" :text "${icon.sun}")
                    (label :class "value" :text "''${brightness}%"))))
              (eventbox :class "hit" :onclick "${popover} dashboard" :cursor "pointer"
                        :tooltip "''${${bat}.capacity}% ''${${bat}.status}"
                (box :class "tile inset hearts ''${${bat}.capacity <= 20 && ${bat}.status != 'Charging' ? 'low' : '''}"
                     :height ${toString tile} :space-evenly false :spacing 3
                  (label :class "icon accent charging" :visible {${bat}.status == "Charging"} :text "${icon.zap}")
                  (for i in hearts
                    (label :class {${bat}.capacity >= i * 10 - 5 ? "heart full" : "heart"}
                           :text {${bat}.capacity >= i * 10 ? "${heart.full}" : ${bat}.capacity >= i * 10 - 5 ? "${heart.half}" : "${heart.empty}"}))))
              (eventbox :class "hit" :onclick "${popover} dashboard" :cursor "pointer"
                (box :class "tile inset" :height ${toString tile} :space-evenly false :spacing 10
                  (label :class "icon accent" :text {clocks[clock.hour12 - 1]})
                  (label :class "value" :text "''${clock.hour} : ''${clock.minute}")))
              (eventbox :class "hit" :onclick "${popover} power" :cursor "pointer"
                (box :class "tile ''${power_open ? 'open' : '''}" :width ${toString tile} :height ${toString tile}
                  (label :class "icon accent" :hexpand true :text "${icon.power}"))))))

        ; A clear surface under any open popover: a click outside closes it.
        (defwindow scrim
          :monitor 0
          :stacking "fg"
          :exclusive false
          :focusable "none"
          :namespace "scrim"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "100%" :anchor "top left")
          (eventbox :class "scrim" :onclick "${popover}"))

        ; A panel: square, edged in the accent, under a title band.
        (defwidget panel [title ?aside]
          (box :class "panel" :orientation "v" :space-evenly false
            (box :class "band" :space-evenly false
              (label :class "band-title" :hexpand true :halign "start" :text title)
              (label :class "band-aside" :visible {aside != ""} :text aside))
            (box :class "panel-body" :orientation "v" :space-evenly false
              (children))))
      '';

      xdg.config.files."eww/dashboard.yuck".text = ''
        (defwidget meter [label icon value ?onchange]
          (box :class "meter" :orientation "v" :space-evenly false
            (box :space-evenly false
              (label :class "caption" :hexpand true :halign "start" :text label)
              (label :class "caption" :text "''${round(value, 0)}%"))
            (box :space-evenly false :spacing 10
              (label :class "icon accent" :text icon)
              (scale :class {onchange == "" ? "bar fixed" : "bar"} :hexpand true :min 0 :max 101
                     :value value :active {onchange != ""} :onchange onchange))))

        (defwidget switch [label value on action]
          (box :class "switch-row" :orientation "v" :space-evenly false
            (label :class "caption" :halign "start" :text label)
            (eventbox :class "hit" :onclick action :cursor "pointer"
              (box :class "button ''${on ? 'on' : '''}" :height 32
                (label :class "value" :hexpand true :limit-width 28 :text value)))))

        (defwindow dashboard
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "6px" :y "6px" :width "300px" :anchor "top left")
          (revealer :reveal dashboard_open :transition "slidedown" :duration "200ms"
            (panel :title "welcome, ${username}"
              (box :class "clock" :orientation "v" :space-evenly false
                (label :class "big" :text "''${clock.hour} : ''${clock.minute}")
                (box :space-evenly false
                  (label :class "caption" :hexpand true :halign "start" :text {clock.weekday})
                  (label :class "caption" :text {clock.date})))
              (box :class "profile" :orientation "v" :space-evenly false :spacing 10
                (box :class "portrait" :halign "center" :width 72 :height 72)
                (label :class "name" :text "${username}")
                (label :class "caption" :text "frieren · asahi linux"))
              (meter :label "battery" :icon {${bat}.status == "Charging" ? "${icon.battery-charging}" : "${icon.battery-full}"}
                     :value {${bat}.capacity})
              (meter :label "brightness" :icon "${icon.sun}" :value brightness
                     :onchange "brightnessctl -q -d apple-panel-bl --min-value=6 set {}%; eww update brightness={}")
              (meter :label "volume" :icon {volume.muted ? "${icon.volume-x}" : "${icon.volume-2}"} :value {volume.level}
                     :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%")
              (switch :label "network" :on {network.enabled}
                      :value {network.kind == "wifi" ? network.ssid : network.kind == "wired" ? "wired" : network.enabled ? "not connected" : "wi-fi off"}
                      :action "${toggle} wifi")
              (switch :label "bluetooth" :on {bluetooth.powered}
                      :value {bluetooth.device != "" ? bluetooth.device : bluetooth.powered ? "on" : "off"}
                      :action "${toggle} bluetooth")
              (box :class "pair" :spacing 8 :homogeneous true
                (eventbox :class "hit" :onclick "${toggle} dnd" :cursor "pointer"
                  (box :class "button ''${dnd ? 'on' : '''}" :height 32
                    (box :space-evenly false :spacing 8 :hexpand true :halign "center"
                    (label :class "icon" :text "${icon.bell-off}")
                    (label :class "value" :text "quiet"))))
                (eventbox :class "hit" :onclick "${toggle} awake" :cursor "pointer"
                  (box :class "button ''${awake ? 'on' : '''}" :height 32
                    (box :space-evenly false :spacing 8 :hexpand true :halign "center"
                    (label :class "icon" :text "${icon.coffee}")
                    (label :class "value" :text "awake"))))))))
      '';

      xdg.config.files."eww/player.yuck".text = ''
        (defwidget control [icon action ?on]
          (eventbox :class "hit" :onclick action :cursor "pointer"
            (box :class "control ''${on == true ? 'on' : '''}" :width 40 :height 32
              (label :class "icon" :hexpand true :text icon))))

        ; Under the music tile.
        (defwindow player
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString (6 + tile + 6 + 150 + 6 + 160 + 6)}px" :y "6px" :width "300px" :anchor "top left")
          (revealer :reveal player_open :transition "slidedown" :duration "200ms"
            (panel :title "now playing" :aside {media.player}
              (overlay :class "stage"
                (box :class "backdrop" :height 208 :style {media.art != "" ? "background-image: url('" + media.art + "');" : ""})
                (box :class "art" :halign "center" :valign "center" :width 176 :height 176
                     :style {media.art != "" ? "background-image: url('" + media.art + "');" : ""}
                  (label :class "icon faint big-icon" :visible {media.art == ""} :text "${icon.disc-3}")))
              (box :class "controls" :halign "center" :space-evenly false :spacing 8
                (control :icon "${icon.skip-back}" :action "playerctl previous")
                (control :icon {media.status == "Playing" ? "${icon.pause}" : "${icon.play}"} :action "playerctl play-pause")
                (control :icon "${icon.skip-forward}" :action "playerctl next")
                (control :icon {looping == "Track" ? "${icon.repeat-1}" : "${icon.repeat}"} :on {looping != "None"} :action "${repeat}"))
              (label :class "track" :limit-width 30 :text {media.title != "" ? media.title : "nothing playing"})
              (label :class "caption artist" :limit-width 34 :text {media.artist})
              (progress :class "elapsed" :value {media.length > 0 ? position * 100000000 / media.length : 0}))))
      '';

      xdg.config.files."eww/power.yuck".text = ''
        (defwidget leave [icon action label]
          (eventbox :class "hit" :cursor "pointer"
                    :onclick "${power} ''${action}"
                    :tooltip {power_armed == action ? "click again to ''${label}" : label}
            (box :class "control ''${power_armed == action ? 'armed' : '''}" :width 40 :height 40
              (label :class "icon" :hexpand true :text {power_armed == action ? "${icon.check}" : icon}))))

        ; Halfway down the right edge, as in the reference.
        (defwindow power
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "6px" :y "0" :anchor "center right")
          (revealer :reveal power_open :transition "slideleft" :duration "200ms"
            (box :class "column" :orientation "v" :space-evenly false :spacing 6
              (leave :icon "${icon.lock}" :action "lock" :label "lock")
              (leave :icon "${icon.moon}" :action "sleep" :label "sleep")
              (leave :icon "${icon.log-out}" :action "logout" :label "log out")
              (leave :icon "${icon.rotate-ccw}" :action "restart" :label "restart")
              (leave :icon "${icon.power}" :action "shutdown" :label "shut down"))))
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
            (box :class "card ''${osd_label == 'muted' || osd_label == 'microphone muted' ? 'muted' : '''}" :space-evenly false :spacing 12
              (label :class "icon accent"
                     :text {osd_kind == "brightness" ? "${icon.sun}" : osd_kind == "microphone" ? (osd_label == "microphone muted" ? "${icon.mic-off}" : "${icon.mic}") : osd_label == "muted" ? "${icon.volume-x}" : "${icon.volume-2}"})
              (progress :class "elapsed" :hexpand true :valign "center" :value osd_value)
              (label :class "value" :width 32 :halign "end" :text "''${osd_value}"))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        // Material roles from the matugen theme (see theme.nix).
        $strip: ${m.surface_container_lowest};
        $surface: ${m.surface_container};
        $well: ${m.surface_container_highest};
        $ink: ${m.on_surface};
        $muted: ${m.on_surface_variant};
        $faint: ${m.outline};
        $hairline: ${m.outline_variant};
        $accent: ${m.primary};
        $on-accent: ${m.on_primary};
        $error: ${m.error};
        $on-error: ${m.on_error};
        $material: ${material};

        // Motion (Material 3): the standard curve, short.
        $standard: cubic-bezier(0.2, 0, 0, 1);
        $fast: 100ms;

        * {
          all: unset;
          border-radius: 0;
          font-family: "Maple Mono NF CN";
          font-size: 12px;
          color: $ink;
        }

        tooltip {
          background-color: $surface;
          border: 1px solid $accent;
          padding: 4px 8px;
        }

        .icon {
          font-family: "lucide";
          font-size: 14px;
        }
        .accent {
          color: $accent;
        }
        .faint {
          color: $faint;
        }
        .value {
          font-weight: bold;
        }
        .dim {
          color: $muted;
        }
        .secondary,
        .caption {
          color: $muted;
        }
        .caption {
          font-size: 11px;
        }

        // A state layer in the content colour: 8 % on hover, 12 % pressed. GTK 3
        // eventboxes take no size or padding, so they only catch the pointer
        // ("hit") and the box inside carries the look.
        @mixin interactive($base) {
          transition: background-color $fast $standard;
          .hit:hover > & {
            background-color: mix($ink, $base, 8%);
          }
          .hit:active > & {
            background-color: mix($ink, $base, 12%);
          }
        }

        // The strip and its tiles.
        .strip {
          background-color: rgba($strip, $material);
        }
        .group {
          margin: 0 6px;
        }
        .tile {
          min-height: ${toString (tile - 2)}px;
          margin-top: ${toString ((strip - tile) / 2)}px;
          background-color: rgba($surface, $material);
          border: 1px solid $accent;
          @include interactive($surface);
        }
        .tile.open {
          background-color: mix($ink, $surface, 12%);
        }
        .inset {
          padding: 0 12px;
        }
        .avatar {
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
        }
        .hit:hover > .avatar {
          opacity: 0.85;
        }
        .notch {
          border: 1px solid $accent;
          border-top: none;
          background-color: #000000;
        }

        .tag .icon {
          color: $faint;
          transition: color $fast $standard;
        }
        .tag.occupied .icon {
          color: $ink;
        }
        .tag.focused .icon {
          color: $accent;
        }
        .tag:hover .icon {
          color: $accent;
        }

        .music .cover {
          background-size: cover;
          background-position: center;
          opacity: 0.35;
        }
        .music-text {
          padding: 0 12px;
        }
        .music .line {
          font-size: 10px;
          font-weight: bold;
        }

        .heart {
          font-size: 13px;
          color: $faint;
        }
        .heart.full {
          color: $accent;
        }
        .hearts.low .heart.full {
          color: $error;
        }
        .charging {
          font-size: 12px;
          margin-right: 4px;
        }

        .scrim {
          background-color: transparent;
        }

        // Panels: the tile's edge, a title band in the accent.
        .panel {
          background-color: rgba($surface, $material);
          border: 1px solid $accent;
        }
        .band {
          background-color: $accent;
          padding: 6px 12px;
        }
        .band-title {
          color: $on-accent;
          font-weight: bold;
          font-style: italic;
        }
        .band-aside {
          color: rgba($on-accent, 0.7);
          font-size: 11px;
        }
        .panel-body {
          padding: 16px;
        }

        .clock {
          margin-bottom: 16px;
        }
        .big {
          font-size: 40px;
          font-weight: bold;
          margin-bottom: 4px;
        }
        .profile {
          border: 1px solid $hairline;
          padding: 16px;
          margin-bottom: 16px;
        }
        .portrait {
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
          border: 1px solid $accent;
        }
        .name {
          font-size: 15px;
          font-weight: bold;
        }

        .meter {
          margin-bottom: 12px;
        }
        scale.bar {
          margin: 4px 0;
        }
        scale.bar trough,
        progressbar trough {
          min-height: 4px;
          background-color: $well;
        }
        scale.bar highlight,
        progressbar progress {
          min-height: 4px;
          background-color: $accent;
        }
        scale.bar slider {
          min-width: 4px;
          min-height: 12px;
          margin: -4px 0;
          background-color: $accent;
          opacity: 0;
          transition: opacity $fast $standard;
        }
        scale.bar:hover slider {
          opacity: 1;
        }
        scale.bar.fixed slider {
          min-width: 0;
        }

        .switch-row {
          margin-top: 4px;
          margin-bottom: 8px;
        }
        .switch-row .caption {
          margin-bottom: 4px;
        }
        // Switches: grey wells; on, the text comes up to full ink and an
        // accent edge marks the left side.
        .button {
          background-color: $well;
          border-left: 3px solid transparent;
          @include interactive($well);
        }
        .button .value {
          padding: 0 12px;
        }
        .button .value,
        .button .icon {
          color: $muted;
        }
        .button.on {
          border-left-color: $accent;
        }
        .button.on .value,
        .button.on .icon {
          color: $ink;
        }
        .pair {
          margin-top: 8px;
        }

        .stage {
          min-height: 208px;
          margin-bottom: 16px;
          border: 1px solid $hairline;
        }
        .backdrop {
          background-size: cover;
          background-position: center;
          opacity: 0.25;
        }
        .art {
          background-size: cover;
          background-position: center;
          border: 1px solid $accent;
          background-color: $well;
        }
        .big-icon {
          font-size: 48px;
        }
        .controls {
          margin-bottom: 16px;
        }
        .control {
          background-color: $well;
          @include interactive($well);
        }
        .control.on {
          background-color: $accent;
        }
        .control.on .icon {
          color: $on-accent;
        }
        .track {
          font-weight: bold;
        }
        .artist {
          margin-bottom: 12px;
        }

        .column {
          background-color: rgba($surface, $material);
          border: 1px solid $accent;
          padding: 6px;
        }
        .control.armed {
          background-color: $error;
        }
        .control.armed .icon {
          color: $on-error;
        }

        .card {
          background-color: rgba($surface, $material);
          border: 1px solid $accent;
          padding: 0 16px;
          min-height: 48px;
        }
        .card.muted progressbar progress {
          background-color: $faint;
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
          pkgs.eww
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

{ lib, username, ... }:
let
  # Lucide, the open icon set closest to SF Symbols: even 2 px strokes on a 24
  # grid with rounded ends. Its glyphs are named after the icons, so the
  # codepoints are read from the font rather than copied in.
  lucideMap =
    pkgs:
    let
      python = pkgs.python3.withPackages (p: [ p.fonttools ]);
      json = pkgs.runCommandLocal "lucide-codepoints.json" { } ''
        ${python}/bin/python3 -I - ${pkgs.lucide}/share/fonts/truetype/Lucide.ttf > $out <<'PY'
        import json, sys
        from fontTools.ttLib import TTFont
        cmap = TTFont(sys.argv[1]).getBestCmap()
        print(json.dumps({name: code for code, name in cmap.items()}))
        PY
      '';
    in
    lib.mapAttrs (_: code: builtins.fromJSON ''"\u${lib.toLower (lib.toHexString code)}"'') (
      builtins.fromJSON (builtins.readFile json)
    );

  # The panel's notch, in logical pixels at the default 1512 x 982: about 185
  # wide. Asahi gives back the 37 rows beside it (show_notch=1).
  notch.width = 185;
  screen = 1512;
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      fonts.packages = [ pkgs.lucide ];
    };

  # The desktop shell, in eww. The 37 rows beside the notch are a black band,
  # so the notch vanishes into it as macOS has it, with soft grey pills
  # floating in the band: the avatar, kanji workspaces from 〇 and the focused
  # window on the left, the track, status and time on the right. The avatar
  # opens a panel after Tail-R's xmonad rice (a big clock, a profile card,
  # the power keys); the status and time open the controls, the track the
  # player. Maple Mono with Lucide icons, in the sakura theme.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      icon = lucideMap pkgs;
      eww = lib.getExe pkgs.eww;

      band = 37;
      pill = 27;
      edge = 10;
      gap = 6;
      widths = {
        music = 210;
        status = 176;
        clock = 148;
      };
      # The player hangs centred under the track, the rightmost pill but two.
      music = {
        right = screen - edge - widths.clock - gap - widths.status - gap;
        centre = music.right - widths.music / 2;
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
              local enabled wired wifi ssid kind
              enabled=$(nmcli -t radio wifi)
              wired=$(nmcli -t -f TYPE,STATE device | grep -c '^ethernet:connected$' || true)
              wifi=$(nmcli -t -f IN-USE,SSID device wifi list --rescan no 2>/dev/null | grep '^\*' | head -1 || true)
              ssid=$(cut -d: -f2- <<< "$wifi")
              if [ "$wired" -gt 0 ]; then kind=wired; elif [ -n "$wifi" ]; then kind=wifi; else kind=none; fi
              jq -cn --arg kind "$kind" --arg ssid "$ssid" \
                --argjson enabled "$([ "$enabled" = enabled ] && echo true || echo false)" \
                '{kind: $kind, ssid: $ssid, enabled: $enabled}'
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
      # file (file:// art as is, remote art fetched once into the cache) and
      # the cover's average colour, darkened, for the player's stage.
      media =
        script "shell-media"
          [
            pkgs.coreutils
            pkgs.curl
            pkgs.imagemagick
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
                tint=""
                if [ -n "$art" ] && [ -f "$art" ]; then
                  tint=$(magick "''${art}[0]" -alpha off -resize '1x1!' -modulate 35,140 -format '#%[hex:u.p{0,0}]' info: 2>/dev/null | cut -c1-7 || true)
                fi
                jq -nc --arg status "$status" --arg title "$title" --arg artist "$artist" --arg art "$art" \
                  --arg tint "$tint" --arg length "''${length:-0}" --arg player "$player" \
                  '{status: $status, title: $title, artist: $artist, art: $art, tint: $tint,
                    length: ($length | tonumber? // 0), player: $player}'
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
        date '+{"hour":"%H","minute":"%M","weekday":"%A","date":"%-d, %B","short":"%a %-d %b"}'
      '';

      brightness = script "shell-brightness" [ pkgs.brightnessctl pkgs.coreutils ] ''
        brightnessctl -d apple-panel-bl -m | cut -d, -f4 | tr -d %
      '';

      # Popovers: one open at a time, over a clear scrim that closes them on
      # any click outside. Content slides in with a revealer, and out before
      # the window closes, so the exit animates too.
      popovers = [
        "dashboard"
        "control"
        "player"
      ];
      popover = script "shell-popover" [ pkgs.coreutils pkgs.eww pkgs.gnugrep ] ''
        want=''${1:-}
        open=$(eww active-windows 2>/dev/null | cut -d: -f1)
        close_all() {
          eww update ${lib.concatMapStringsSep " " (p: "${p}_open=false") popovers} power_armed=""
          sleep 0.25
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

      toggle =
        script "shell-toggle"
          [
            pkgs.bluez
            pkgs.gnugrep
            pkgs.networkmanager
          ]
          ''
            wifi() { [ "$(nmcli radio wifi)" = enabled ]; }
            bluetooth() { bluetoothctl show | grep -q "Powered: yes"; }
            case "''${1:-}" in
              wifi) if wifi; then nmcli radio wifi off; else nmcli radio wifi on; fi ;;
              bluetooth) if bluetooth; then bluetoothctl power off; else bluetoothctl power on; fi ;;
            esac >/dev/null
          '';

      # Lock and sleep act at once; the rest ask for a second click within three
      # seconds, as the button turns to say.
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

      art = ''{media.art != "" ? "background-image: url('" + media.art + "');" : ""}'';

      # Workspaces in kanji, counting from nought.
      numerals = builtins.toJSON [
        "〇"
        "一"
        "二"
        "三"
        "四"
        "五"
        "六"
        "七"
        "八"
        "九"
      ];

      batteryIcon = ''
        {${bat}.status == "Charging" ? "${icon.battery-charging}"
          : ${bat}.capacity > 80 ? "${icon.battery-full}"
          : ${bat}.capacity > 45 ? "${icon.battery-medium}"
          : ${bat}.capacity > 15 ? "${icon.battery-low}"
          : "${icon.battery-warning}"}'';
      volumeIcon = ''
        {volume.muted ? "${icon.volume-x}" : volume.level > 66 ? "${icon.volume-2}" : volume.level > 0 ? "${icon.volume-1}" : "${icon.volume}"}'';
    in
    {
      packages = [ pkgs.eww ];

      xdg.config.files."eww/eww.yuck".text = ''
        (deflisten kwm :initial '{"tags":[],"app_id":"","title":""}' "${tags}")
        (deflisten volume :initial '{"level":0,"muted":false}' "${volume}")
        (deflisten network :initial '{"kind":"none","ssid":"","enabled":true}' "${network}")
        (deflisten media :initial '{"status":"","title":"","artist":"","art":"","tint":"","length":0,"player":""}' "${media}")
        (defpoll bluetooth :interval "5s" :initial '{"powered":false,"device":""}' "${bluetooth}")
        (defpoll clock :interval "5s" :initial '{"hour":"","minute":"","weekday":"","date":"","short":""}' "${clock}")
        (defpoll brightness :interval "5s" :initial "0" "${brightness}")

        ${lib.concatMapStringsSep "\n" (p: "(defvar ${p}_open false)") popovers}
        (defvar power_armed "")
        (defpoll position :interval "1s" :initial "0" :run-while player_open "${position}")
        (defpoll looping :interval "2s" :initial "None" :run-while player_open "playerctl loop 2>/dev/null || echo None")

        (defvar numerals '${numerals}')

        (include "./widgets.yuck")
        (include "./bar.yuck")
        (include "./dashboard.yuck")
        (include "./control.yuck")
        (include "./player.yuck")
        (include "./osd.yuck")
      '';

      xdg.config.files."eww/widgets.yuck".text = ''
        ; GTK 3 eventboxes take no size or padding, so in these the eventbox
        ; only catches the pointer and the box inside carries the look.

        ; A pill in the band.
        (defwidget pill [?class ?width ?onclick ?onscroll ?tooltip ?hexpand]
          (eventbox :class "hit" :onclick onclick :onscroll onscroll :tooltip tooltip
                    :cursor {onclick != "" ? "pointer" : "default"}
            (box :class "pill ''${class}" :width {width == "" ? 0 : width} :height ${toString pill}
                 :space-evenly false
              (children))))

        ; A key in a panel.
        (defwidget key [?class ?width height onclick ?tooltip]
          (eventbox :class "hit" :onclick onclick :cursor "pointer" :tooltip tooltip
            (box :class "key ''${class}" :width {width == "" ? 0 : width} :height height
              (children))))

        ; A panel, square to the band's edge but rounded below it.
        (defwidget panel [?class]
          (box :class "panel ''${class}" :orientation "v" :space-evenly false
            (children)))
      '';

      xdg.config.files."eww/bar.yuck".text = ''
        ; The band: the ${toString band} rows beside the notch, black like the
        ; notch, with ${toString pill}-tall pills floating in it.
        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "${toString band}px" :anchor "top center")
          (centerbox :class "band"
            (box :class "side" :halign "start" :valign "center" :space-evenly false :spacing ${toString gap}
              (eventbox :class "hit" :onclick "${popover} dashboard" :cursor "pointer" :tooltip "${username}"
                (box :class "avatar ''${dashboard_open ? 'open' : '''}" :width ${toString pill} :height ${toString pill}))
              (pill :class "workspaces"
                (box :space-evenly false :spacing 2
                  (for tag in {kwm.tags}
                    (eventbox :cursor "pointer" :visible {tag.focused || tag.occupied || tag.id <= 5}
                              :onclick "echo set_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                              :onrightclick "echo toggle_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                      (box :class {tag.focused ? "ws focused" : tag.occupied ? "ws occupied" : "ws"}
                           :width 23 :height 21
                        (label :hexpand true :text {numerals[tag.id - 1]}))))))
              (pill :class "title" :visible {kwm.title != "" || kwm.app_id != ""}
                (label :class "strong" :limit-width 40 :text {kwm.title != "" ? kwm.title : kwm.app_id})))
            (box :class "notch" :width ${toString (notch.width + 2 * 8)})
            (box :class "side" :halign "end" :valign "center" :space-evenly false :spacing ${toString gap}
              (pill :class {player_open ? "music open" : "music"} :width ${toString widths.music}
                    :visible {media.title != ""} :onclick "${popover} player"
                (box :space-evenly false :spacing 8
                  (box :class "thumb" :width 19 :height 19 :valign "center" :visible {media.art != ""} :style ${art})
                  (label :class "icon dim" :visible {media.art == ""} :text "${icon.music}")
                  (label :class "strong" :limit-width 22 :text {media.title})))
              (pill :class {control_open ? "open" : ""} :width ${toString widths.status}
                    :onclick "${popover} control" :onscroll "osd volume-{}"
                (box :hexpand true :halign "center" :space-evenly false :spacing 14
                  (label :class {network.kind == "none" ? "icon dim" : "icon"}
                         :text {network.kind == "wired" ? "${icon.ethernet-port}" : network.kind == "wifi" ? "${icon.wifi}" : "${icon.wifi-off}"})
                  (label :class {bluetooth.powered ? "icon" : "icon dim"}
                         :text {bluetooth.device != "" ? "${icon.bluetooth-connected}" : bluetooth.powered ? "${icon.bluetooth}" : "${icon.bluetooth-off}"})
                  (label :class "icon" :text ${volumeIcon})
                  (box :space-evenly false :spacing 6
                    :class {${bat}.capacity <= 15 && ${bat}.status != "Charging" ? "low" : ""}
                    (label :class "icon" :text ${batteryIcon})
                    (label :class "strong" :text "''${${bat}.capacity}%"))))
              (pill :class {control_open ? "open" : ""} :width ${toString widths.clock} :onclick "${popover} control"
                (box :hexpand true :halign "center" :space-evenly false :spacing 8
                  (label :class "dim" :text {clock.short})
                  (label :class "strong" :text "''${clock.hour}:''${clock.minute}"))))))

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

      xdg.config.files."eww/dashboard.yuck".text = ''
        (defwidget leave [glyph action label]
          (key :class {power_armed == action ? "armed" : ""} :height 40
               :onclick "${power} ''${action}"
               :tooltip {power_armed == action ? "click again to ''${label}" : label}
            (label :class "icon" :hexpand true :text {power_armed == action ? "${icon.check}" : glyph})))

        ; From the avatar: the time, who and what this is, and the way out.
        (defwindow dashboard
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString edge}px" :y "${toString gap}px" :width "280px" :anchor "top left")
          (revealer :reveal dashboard_open :transition "slidedown" :duration "250ms"
            (panel
              (label :class "big-clock" :text "''${clock.hour} : ''${clock.minute}")
              (box :class "dateline" :space-evenly false
                (label :class "caption" :hexpand true :halign "start" :text {clock.weekday})
                (label :class "caption" :text {clock.date}))
              (box :class "card profile" :orientation "v" :space-evenly false :spacing 6
                (box :class "portrait" :halign "center" :width 84 :height 84)
                (label :class "name" :text "${username}")
                (label :class "caption" :text "frieren · asahi linux"))
              (box :class "keys" :spacing 8 :homogeneous true
                (leave :glyph "${icon.lock}" :action "lock" :label "lock")
                (leave :glyph "${icon.moon}" :action "sleep" :label "sleep")
                (leave :glyph "${icon.rotate-ccw}" :action "restart" :label "restart")
                (leave :glyph "${icon.power}" :action "shutdown" :label "shut down")))))
      '';

      xdg.config.files."eww/control.yuck".text = ''
        (defwidget tile [glyph title detail on onclick]
          (key :class {on ? "tile on" : "tile"} :height 56 :onclick onclick
            (box :class "tile-body" :space-evenly false :spacing 10
              (box :class "badge" :width 32 :height 32 :valign "center"
                (label :class "icon" :hexpand true :text glyph))
              (box :orientation "v" :valign "center" :space-evenly false
                (label :class "strong" :halign "start" :text title)
                (label :class "caption" :halign "start" :limit-width 14 :text detail)))))

        (defwidget meter [label glyph value ?onchange]
          (box :class "meter" :orientation "v" :space-evenly false :spacing 6
            (box :space-evenly false
              (label :class "caption" :hexpand true :halign "start" :text label)
              (label :class "caption" :text "''${round(value, 0)}%"))
            (box :space-evenly false :spacing 10
              (label :class "icon" :text glyph)
              (scale :class {onchange == "" ? "bar fixed" : "bar"} :hexpand true :min 0 :max 101
                     :value value :active {onchange != ""} :onchange onchange))))

        ; From the status and the time.
        (defwindow control
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString edge}px" :y "${toString gap}px" :width "320px" :anchor "top right")
          (revealer :reveal control_open :transition "slidedown" :duration "250ms"
            (panel
              (box :class "tiles" :spacing 8 :homogeneous true
                (tile :glyph {network.enabled ? "${icon.wifi}" : "${icon.wifi-off}"} :title "Wi-Fi"
                      :detail {network.kind == "wifi" ? network.ssid : network.kind == "wired" ? "Wired" : network.enabled ? "Not connected" : "Off"}
                      :on {network.enabled} :onclick "${toggle} wifi")
                (tile :glyph {bluetooth.powered ? "${icon.bluetooth}" : "${icon.bluetooth-off}"} :title "Bluetooth"
                      :detail {bluetooth.device != "" ? bluetooth.device : bluetooth.powered ? "On" : "Off"}
                      :on {bluetooth.powered} :onclick "${toggle} bluetooth"))
              (box :class "card meters" :orientation "v" :space-evenly false
                (meter :label "Brightness" :glyph "${icon.sun}" :value brightness
                       :onchange "brightnessctl -q -d apple-panel-bl --min-value=6 set {}%; eww update brightness={}")
                (meter :label "Volume" :glyph ${volumeIcon} :value {volume.level}
                       :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%")
                (meter :label {${bat}.status == "Charging" ? "Battery, charging" : "Battery"} :glyph ${batteryIcon}
                       :value {${bat}.capacity}))
              (box :class "dateline foot" :space-evenly false
                (label :class "caption" :hexpand true :halign "start" :text "''${clock.weekday}, ''${clock.date}")
                (label :class "caption" :text "''${clock.hour}:''${clock.minute}")))))
      '';

      xdg.config.files."eww/player.yuck".text = ''
        ; Centred under the track.
        (defwindow player
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString (music.centre - 150)}px" :y "${toString gap}px" :width "300px" :anchor "top left")
          (revealer :reveal player_open :transition "slidedown" :duration "250ms"
            (panel
              (overlay :class "stage"
                (box :class "stage-ground" :height 200
                     :style {media.tint != "" ? "background-color: ''${media.tint};" : ""})
                (box :class "cover" :halign "center" :valign "center" :width 160 :height 160 :style ${art}
                  (label :class "icon dim cover-icon" :hexpand true :visible {media.art == ""} :text "${icon.music}")))
              (label :class "track" :limit-width 30 :text {media.title != "" ? media.title : "Nothing playing"})
              (label :class "caption artist" :limit-width 36 :visible {media.artist != ""} :text {media.artist})
              (progress :class "elapsed" :value {media.length > 0 ? position * 100000000 / media.length : 0})
              (box :class "controls" :halign "center" :space-evenly false :spacing 14
                (key :class "round" :width 36 :height 36 :onclick "${repeat}"
                  (label :class {looping != "None" ? "icon accent" : "icon dim"} :hexpand true
                         :text {looping == "Track" ? "${icon.repeat-1}" : "${icon.repeat}"}))
                (key :class "round" :width 40 :height 40 :onclick "playerctl previous"
                  (label :class "icon" :hexpand true :text "${icon.skip-back}"))
                (key :class "round primary" :width 48 :height 48 :onclick "playerctl play-pause"
                  (label :class "icon big-icon" :hexpand true :text {media.status == "Playing" ? "${icon.pause}" : "${icon.play}"}))
                (key :class "round" :width 40 :height 40 :onclick "playerctl next"
                  (label :class "icon" :hexpand true :text "${icon.skip-forward}"))
                (box :width 36)))))
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
          :geometry (geometry :x "0" :y "96px" :width "260px" :anchor "bottom center")
          (revealer :reveal osd_open :transition "crossfade" :duration "150ms"
            (box :class {osd_label == "muted" || osd_label == "microphone muted" ? "osd muted" : "osd"}
                 :height 44 :space-evenly false :spacing 12
              (label :class "icon"
                     :text {osd_kind == "brightness" ? "${icon.sun}" : osd_kind == "microphone" ? (osd_label == "microphone muted" ? "${icon.mic-off}" : "${icon.mic}") : osd_label == "muted" ? "${icon.volume-x}" : "${icon.volume-2}"})
              (progress :class "elapsed" :hexpand true :valign "center" :value osd_value)
              (label :class "strong" :width 28 :halign "end" :text "''${osd_value}"))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        // Sakura (see theme.nix): soft greys a breath off neutral, a calm pink.
        $text: ${palette.surface.text};
        $dim: ${palette.surface.textDim};
        $faint: ${palette.surface.neutral4};
        $base: ${palette.surface.background};
        $raised: ${palette.surface.neutral0};
        $key: ${palette.surface.neutral1};
        $well: ${palette.surface.neutral2};
        $accent: ${palette.ui.accent};
        $error: ${palette.status.error};

        $standard: cubic-bezier(0.2, 0, 0, 1);
        $fast: 120ms;
        $hairline: 1px solid rgba($text, 0.07);

        * {
          all: unset;
          font-family: "Maple Mono NF CN";
          font-size: 12px;
          color: $text;
        }

        tooltip {
          background-color: $raised;
          border: $hairline;
          border-radius: 8px;
          padding: 4px 10px;
        }

        // Lucide: each icon in a box its own size, centred on the text.
        .icon {
          font-family: "lucide";
          font-size: 15px;
          min-width: 16px;
        }
        .strong {
          font-weight: 600;
        }
        .dim {
          color: $dim;
        }
        .accent {
          color: $accent;
        }
        .caption {
          color: $dim;
          font-size: 11px;
        }
        .low .icon,
        .low .strong {
          color: $error;
        }

        // The band, black like the notch.
        .band {
          background-color: #000000;
        }
        .side {
          margin: 0 ${toString edge}px;
        }
        .pill {
          background-color: $raised;
          border: $hairline;
          border-radius: 9px;
          padding: 0 12px;
          transition: background-color $fast $standard;
        }
        .hit:hover > .pill {
          background-color: mix($text, $raised, 6%);
        }
        .pill.open {
          background-color: mix($text, $raised, 10%);
        }

        .avatar {
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
          border-radius: 50%;
          box-shadow: inset 0 0 0 1px rgba($text, 0.12);
          transition: box-shadow $fast $standard;
        }
        .hit:hover > .avatar,
        .avatar.open {
          box-shadow: inset 0 0 0 2px $accent;
        }

        .workspaces {
          padding: 0 3px;
        }
        .ws {
          border-radius: 6px;
          color: $faint;
          transition: background-color $fast $standard, color $fast $standard;
        }
        .ws label {
          color: inherit;
          font-size: 12px;
        }
        .ws.occupied {
          color: $text;
        }
        .ws.focused {
          background-color: rgba($accent, 0.16);
          color: $accent;
        }
        .ws.focused label {
          font-weight: bold;
        }
        eventbox:hover > .ws:not(.focused) {
          background-color: rgba($text, 0.07);
        }

        .thumb {
          background-size: cover;
          background-position: center;
          border-radius: 5px;
        }

        .scrim {
          background-color: transparent;
        }

        // Panels: lifted greys, a hairline, generous corners.
        .panel {
          background-color: rgba($raised, 0.97);
          border: $hairline;
          border-radius: 18px;
          padding: 16px;
        }
        .card {
          background-color: rgba($text, 0.035);
          border: $hairline;
          border-radius: 14px;
        }
        .key {
          background-color: $key;
          border-radius: 12px;
          transition: background-color $fast $standard;
        }
        .hit:hover > .key {
          background-color: mix($text, $key, 8%);
        }
        .key.armed {
          background-color: $accent;
        }
        .key.armed .icon {
          color: $base;
        }
        .key.round {
          border-radius: 50%;
          background-color: transparent;
        }
        .hit:hover > .key.round {
          background-color: rgba($text, 0.08);
        }
        .key.round.primary {
          background-color: $accent;
        }
        .key.round.primary .icon {
          color: $base;
        }
        .hit:hover > .key.round.primary {
          background-color: mix($text, $accent, 12%);
        }

        .big-clock {
          font-size: 38px;
          font-weight: bold;
          color: mix($accent, $text, 25%);
          margin: 4px 0 2px;
        }
        .dateline {
          margin: 0 2px 14px;
        }
        .dateline.foot {
          margin: 12px 4px 0;
        }
        .profile {
          padding: 18px 0 14px;
          margin-bottom: 12px;
        }
        .portrait {
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
          border-radius: 50%;
          box-shadow: inset 0 0 0 1px rgba($text, 0.12);
          margin-bottom: 6px;
        }
        .name {
          font-size: 16px;
          font-weight: bold;
        }

        .tiles {
          margin-bottom: 12px;
        }
        .tile-body {
          padding: 0 12px;
        }
        .badge {
          background-color: $well;
          border-radius: 50%;
        }
        .tile.on .badge {
          background-color: $accent;
        }
        .tile.on .badge .icon {
          color: $base;
        }

        .meters {
          padding: 14px 14px 2px;
        }
        .meter {
          margin-bottom: 12px;
        }
        scale.bar trough,
        progressbar trough {
          min-height: 6px;
          border-radius: 99px;
          background-color: $well;
        }
        scale.bar highlight,
        progressbar progress {
          min-height: 6px;
          border-radius: 99px;
          background-color: $accent;
        }
        scale.bar slider {
          min-width: 14px;
          min-height: 14px;
          margin: -4px 0;
          border-radius: 50%;
          background-color: $text;
          opacity: 0;
          transition: opacity $fast $standard;
        }
        scale.bar:hover slider {
          opacity: 1;
        }
        scale.bar.fixed slider {
          min-width: 0;
          min-height: 0;
        }

        .stage {
          margin-bottom: 14px;
        }
        .stage-ground {
          border-radius: 12px;
          background-color: $well;
        }
        .cover {
          background-size: cover;
          background-position: center;
          background-color: $key;
          border-radius: 8px;
          box-shadow: 0 0 22px 2px rgba(#ffffff, 0.22);
        }
        .cover-icon {
          font-size: 40px;
        }
        .track {
          font-size: 13px;
          font-weight: bold;
        }
        .artist {
          margin-top: 2px;
        }
        .elapsed {
          margin: 14px 4px 12px;
        }
        progressbar trough {
          min-height: 4px;
        }
        progressbar progress {
          min-height: 4px;
        }
        .big-icon {
          font-size: 19px;
        }

        .osd {
          background-color: rgba($raised, 0.97);
          border: $hairline;
          border-radius: 14px;
          padding: 0 16px;
        }
        .osd.muted progressbar progress {
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

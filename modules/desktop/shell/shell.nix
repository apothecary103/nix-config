{ lib, username, ... }:
let
  # The panel's notch, in logical pixels at the default 1512 x 982: about 185
  # wide and 32 deep. Asahi gives back the 37 rows beside it (show_notch=1).
  notch = {
    width = 185;
    height = 32;
  };
  screen = 1512;
in
{
  # The desktop shell, in eww, after Tail-R's xmonad rice (xmonad-eww-dotfiles,
  # "how I spent my summer vacation"): dark modules edged in the accent on a
  # light, translucent strip, Nerd Font glyphs (pac-man, cherries, ghosts,
  # hearts), and a dashboard, a player and a power column that drop from it.
  # The notch is one more module, hung from the top edge. Colours come from
  # the matugen theme: its accent, and its surfaces with the hue taken out,
  # since the rice is grey and pink.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      m = palette.native;
      eww = lib.getExe pkgs.eww;

      # Nerd Font glyphs by name, as Maple Mono NF carries them.
      nf =
        let
          names = builtins.fromJSON (
            builtins.readFile "${pkgs.nerd-font-patcher}/share/glyphnames.json"
          );
          hex = n: lib.toLower (lib.fixedWidthString 4 "0" (lib.toHexString n));
          char =
            code:
            builtins.fromJSON (
              ''"''
              + (
                if code < 65536 then
                  "\\u${hex code}"
                else
                  let
                    c = code - 65536;
                  in
                  "\\u${hex (55296 + c / 1024)}\\u${hex (56320 + lib.mod c 1024)}"
              )
              + ''"''
            );
        in
        lib.mapAttrs (_: g: char (lib.fromHexString g.code)) (
          lib.filterAttrs (_: g: lib.isAttrs g && g ? code) names
        );

      # Until river blurs what is behind them, the modules stay nearly opaque.
      material = "0.96";

      # The strip runs past the notch's 37 rows, so the notch module can hang
      # below the notch like the rest of the row.
      strip = 46;
      tile = 34;
      margin = (strip - tile) / 2;
      gap = 8;
      notchModule = notch.width + 20;
      half = (screen - notchModule) / 2 - 2 * gap;
      widths = {
        launcher = tile;
        workspaces = 170;
        music = 230;
        clock = 100;
        hearts = 196;
        power = tile;
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
        date '+{"hour":"%H","minute":"%M","weekday":"%A","date":"%-d, %B"}'
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

      # Sleep acts at once; the rest ask for a second click within three
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
                sleep) systemctl suspend ;;
                logout) loginctl terminate-session "$(loginctl show-user "$USER" -p Display --value)" ;;
                restart) systemctl reboot ;;
                shutdown) systemctl poweroff ;;
              esac
            }
            case "$1" in
              sleep) act "$1" ;;
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

      # The rice's battery: ten hearts by tens, the last partial one half
      # filled, or pulsing while charging.
      heart =
        i:
        lib.concatStrings [
          "{${bat}.capacity >= ${toString (i * 10)} ? \"${nf.md-cards_heart}\""
          " : ${bat}.capacity > ${toString (i * 10 - 10)}"
          " ? (${bat}.status == \"Charging\" ? \"${nf.md-heart_pulse}\" : \"${nf.md-heart_half_full}\")"
          " : \"${nf.md-cards_heart_outline}\"}"
        ];

      art = ''{media.art != "" ? "background-image: url('" + media.art + "');" : ""}'';
    in
    {
      packages = [ pkgs.eww ];

      xdg.config.files."eww/eww.yuck".text = ''
        (deflisten kwm :initial '{"tags":[],"app_id":"","title":""}' "${tags}")
        (deflisten volume :initial '{"level":0,"muted":false}' "${volume}")
        (deflisten network :initial '{"kind":"none","ssid":"","enabled":true}' "${network}")
        (deflisten media :initial '{"status":"","title":"","artist":"","art":"","tint":"","length":0,"player":""}' "${media}")
        (defpoll bluetooth :interval "5s" :initial '{"powered":false,"device":""}' "${bluetooth}")
        (defpoll clock :interval "5s" :initial '{"hour":"","minute":"","weekday":"","date":""}' "${clock}")
        (defpoll brightness :interval "5s" :initial "0" "${brightness}")

        ${lib.concatMapStringsSep "\n" (p: "(defvar ${p}_open false)") popovers}
        (defvar power_armed "")
        (defpoll position :interval "1s" :initial "0" :run-while player_open "${position}")
        (defpoll looping :interval "2s" :initial "None" :run-while player_open "playerctl loop 2>/dev/null || echo None")

        (include "./widgets.yuck")
        (include "./bar.yuck")
        (include "./dashboard.yuck")
        (include "./player.yuck")
        (include "./power.yuck")
        (include "./osd.yuck")
      '';

      xdg.config.files."eww/widgets.yuck".text = ''
        ; GTK 3 eventboxes take no size or padding, so in both of these the
        ; eventbox only catches the pointer and the box inside carries the look.

        ; A bar module: dark, rounded, edged in the accent.
        (defwidget module [?class ?width ?onclick ?onscroll ?tooltip ?hexpand]
          (eventbox :class "hit" :onclick onclick :onscroll onscroll :tooltip tooltip
                    :cursor {onclick != "" ? "pointer" : "default"} :hexpand {hexpand == true}
            (box :class "module ''${class}" :width {width == "" ? 0 : width} :height ${toString tile}
                 :hexpand {hexpand == true} :space-evenly false
              (children))))

        ; A rounded grey key, as the rice's dashboard and player have.
        (defwidget key [?class ?width height onclick ?tooltip]
          (eventbox :class "hit" :onclick onclick :cursor "pointer" :tooltip tooltip
            (box :class "key ''${class}" :width {width == "" ? 0 : width} :height height
              (children))))
      '';

      xdg.config.files."eww/bar.yuck".text = ''
        ; A ${toString strip}-tall strip: the rows beside the notch and a few
        ; below, with ${toString tile}-tall modules in two halves either side of
        ; it, and the notch dressed as a module of its own.
        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "${toString strip}px" :anchor "top center")
          (centerbox :class "strip"
            (box :class "half" :width ${toString half} :valign "start" :space-evenly false :spacing ${toString gap}
              (module :class "launcher" :width ${toString widths.launcher} :onclick "${popover} dashboard"
                (label :class "glyph accent launcher-glyph" :hexpand true :text "${nf.md-pac_man}"))
              (module :width ${toString widths.workspaces}
                (box :hexpand true :halign "center" :space-evenly false :spacing 16
                  (for tag in {kwm.tags}
                    (eventbox :class "tag" :cursor "pointer"
                              :visible {tag.focused || tag.occupied || tag.id <= 5}
                              :tooltip "''${tag.id}"
                              :onclick "echo set_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                              :onrightclick "echo toggle_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
                      (label :class {tag.focused ? "glyph ws active" : tag.occupied ? "glyph ws occupied" : "glyph ws empty"}
                             :text {tag.focused ? "${nf.md-fruit_cherries}" : tag.occupied ? "${nf.md-ghost}" : "${nf.md-circle_small}"})))))
              (module :hexpand true
                (box :hexpand true :halign "center" :space-evenly false :spacing 8
                  (label :class "glyph" :text "${nf.md-window_restore}")
                  (label :class "value" :limit-width 18
                         :text {kwm.title != "" ? kwm.title : kwm.app_id != "" ? kwm.app_id : "desktop"})))
              (module :class {media.title == "" ? "music idle" : "music"} :width ${toString widths.music}
                      :onclick "${popover} player"
                (overlay :hexpand true
                  (box :class "music-wash" :style ${art})
                  (box :space-evenly false :spacing 10
                    (box :class "thumb" :width ${toString (tile - 8)} :height ${toString (tile - 8)} :valign "center"
                         :visible {media.art != ""} :style ${art})
                    (box :orientation "v" :valign "center" :space-evenly false :visible {media.title != ""}
                      (label :class "line" :halign "start" :limit-width 22 :text {media.title})
                      (label :class "line" :halign "start" :limit-width 22 :text {media.artist}))
                    (box :hexpand true :halign "center" :space-evenly false :spacing 8 :visible {media.title == ""}
                      (label :class "glyph dim" :text "${nf.md-music}")
                      (label :class "value dim" :text "silence"))))))
            (box :class "notch" :width ${toString notchModule} :height ${toString (strip - margin)} :valign "start")
            (box :class "half" :width ${toString half} :valign "start" :space-evenly false :spacing ${toString gap}
              (module :hexpand true :onclick "${popover} dashboard" :onscroll "osd volume-{}"
                (box :hexpand true :halign "center" :space-evenly false :spacing 14
                  (box :space-evenly false :spacing 8
                    (label :class {bluetooth.powered ? "glyph" : "glyph dim"} :text {bluetooth.powered ? "${nf.md-bluetooth}" : "${nf.md-bluetooth_off}"})
                    (label :class "value" :limit-width 10 :visible {bluetooth.device != ""} :text {bluetooth.device}))
                  (box :space-evenly false :spacing 8
                    (label :class "glyph accent" :text {network.kind == "none" ? "${nf.md-wifi_strength_off}" : "${nf.md-wifi_strength_4}"})
                    (label :class "value" :text {network.kind == "none" ? "offline" : "online"}))
                  (box :space-evenly false :spacing 8
                    (label :class "glyph" :text {volume.muted ? "${nf.md-volume_off}" : "${nf.seti-audio}"})
                    (label :class "value" :text "''${volume.level}%"))
                  (box :space-evenly false :spacing 8
                    (label :class "glyph" :text "${nf.oct-sun}")
                    (label :class "value" :text "''${brightness}%"))))
              (module :width ${toString widths.hearts} :onclick "${popover} dashboard"
                      :tooltip "''${${bat}.capacity}%, ''${${bat}.status}"
                (box :hexpand true :halign "center" :space-evenly false :spacing 1
                     :class {${bat}.capacity <= 20 && ${bat}.status != "Charging" ? "hearts low" : "hearts"}
                  ${
                    lib.concatMapStringsSep "\n                  " (
                      i: ''(label :class "glyph heart" :text ${heart i})''
                    ) (lib.range 1 10)
                  }))
              (module :width ${toString widths.clock} :onclick "${popover} dashboard"
                (box :hexpand true :halign "center" :space-evenly false :spacing 10
                  (label :class "glyph accent" :text "${nf.fa-clock_o}")
                  (label :class "value" :text "''${clock.hour} : ''${clock.minute}")))
              (module :class {power_open ? "open" : ""} :width ${toString widths.power} :onclick "${popover} power"
                (label :class "glyph accent" :hexpand true :text "${nf.md-power}")))))

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
        (defwidget meter [label glyph value ?onchange]
          (box :class "meter" :orientation "v" :space-evenly false :spacing 4
            (box :space-evenly false
              (label :class "caption" :hexpand true :halign "start" :text label)
              (label :class "caption" :text "''${round(value, 0)}%"))
            (box :space-evenly false :spacing 10
              (label :class "glyph meter-glyph" :text glyph)
              (scale :class {onchange == "" ? "bar fixed" : "bar"} :hexpand true :min 0 :max 101
                     :value value :active {onchange != ""} :onchange onchange))))

        (defwidget connection [label value onclick on]
          (box :class "connection" :orientation "v" :space-evenly false :spacing 6
            (label :class "caption" :halign "start" :text label)
            (key :class {on ? "pill" : "pill off"} :height 38 :onclick onclick
              (label :class "value" :hexpand true :limit-width 24 :text value))))

        (defwindow dashboard
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString gap}px" :y "${toString gap}px" :width "280px" :anchor "top left")
          (revealer :reveal dashboard_open :transition "slidedown" :duration "250ms"
            (box :class "panel" :orientation "v" :space-evenly false
              (label :class "big-clock" :text "''${clock.hour} : ''${clock.minute}")
              (box :class "dateline" :space-evenly false
                (label :class "caption" :hexpand true :halign "start" :text {clock.weekday})
                (label :class "caption" :text {clock.date}))
              (box :class "profile" :orientation "v" :space-evenly false :spacing 10
                (box :class "portrait" :halign "center" :width 96 :height 96)
                (label :class "name" :text "${username}"))
              (meter :label "battery" :value {${bat}.capacity}
                     :glyph {${bat}.status == "Charging" ? "${nf.md-battery_charging}" : "${nf.fa-battery_full}"})
              (meter :label "brightness" :glyph "${nf.oct-sun}" :value brightness
                     :onchange "brightnessctl -q -d apple-panel-bl --min-value=6 set {}%; eww update brightness={}")
              (meter :label "volume" :glyph {volume.muted ? "${nf.md-volume_off}" : "${nf.seti-audio}"} :value {volume.level}
                     :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%")
              (connection :label "Network" :on {network.kind != "none"} :onclick "${toggle} wifi"
                          :value {network.kind == "wifi" ? network.ssid : network.kind == "wired" ? "wired" : network.enabled ? "not connected" : "wi-fi off"})
              (connection :label "Bluetooth" :on {bluetooth.powered} :onclick "${toggle} bluetooth"
                          :value {bluetooth.device != "" ? bluetooth.device : bluetooth.powered ? "on" : "off"}))))
      '';

      xdg.config.files."eww/player.yuck".text = ''
        ; Centred under the music module.
        (defwindow player
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString (gap + half - widths.music / 2 - 150)}px" :y "${toString gap}px" :width "300px" :anchor "top left")
          (revealer :reveal player_open :transition "slidedown" :duration "250ms"
            (box :class "panel" :orientation "v" :space-evenly false
              (overlay :class "stage"
                (box :class "stage-ground" :height 196
                     :style {media.tint != "" ? "background-color: ''${media.tint};" : ""})
                (box :class "cover" :halign "center" :valign "center" :width 156 :height 156 :style ${art}
                  (label :class "glyph dim cover-glyph" :hexpand true :visible {media.art == ""} :text "${nf.md-music}")))
              (box :class "controls" :halign "center" :space-evenly false :spacing 10
                (key :width 38 :height 36 :onclick "playerctl previous"
                  (label :class "glyph" :hexpand true :text "${nf.md-skip_previous}"))
                (key :width 38 :height 36 :onclick "playerctl play-pause"
                  (label :class "glyph" :hexpand true :text {media.status == "Playing" ? "${nf.md-pause}" : "${nf.md-play}"}))
                (key :width 38 :height 36 :onclick "playerctl next"
                  (label :class "glyph" :hexpand true :text "${nf.md-skip_next}"))
                (key :class {looping != "None" ? "lit" : ""} :width 38 :height 36 :onclick "${repeat}"
                  (label :class "glyph" :hexpand true :text {looping == "Track" ? "${nf.md-repeat_once}" : "${nf.md-repeat}"})))
              (label :class "track" :limit-width 30 :text {media.title != "" ? media.title : "nothing playing"})
              (label :class "track" :limit-width 30 :visible {media.artist != ""} :text {media.artist})
              (progress :class "elapsed" :value {media.length > 0 ? position * 100000000 / media.length : 0}))))
      '';

      xdg.config.files."eww/power.yuck".text = ''
        (defwidget leave [glyph action label]
          (key :class {power_armed == action ? "armed" : ""} :width 40 :height 40
               :onclick "${power} ''${action}"
               :tooltip {power_armed == action ? "again to ''${label}" : label}
            (label :class "glyph" :hexpand true :text {power_armed == action ? "${nf.md-check}" : glyph})))

        ; Halfway down the right edge, as in the rice.
        (defwindow power
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString gap}px" :y "0" :anchor "center right")
          (revealer :reveal power_open :transition "slideleft" :duration "250ms"
            (box :class "panel column" :orientation "v" :space-evenly false :spacing 10
              (leave :glyph "${nf.md-power}" :action "shutdown" :label "shut down")
              (leave :glyph "${nf.md-power_sleep}" :action "sleep" :label "sleep")
              (leave :glyph "${nf.md-logout_variant_2}" :action "logout" :label "log out")
              (leave :glyph "${nf.md-replay}" :action "restart" :label "restart"))))
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
            (box :class {osd_label == "muted" || osd_label == "microphone muted" ? "module osd muted" : "module osd"}
                 :height 44 :space-evenly false :spacing 12
              (label :class "glyph"
                     :text {osd_kind == "brightness" ? "${nf.oct-sun}" : osd_kind == "microphone" ? (osd_label == "microphone muted" ? "${nf.md-microphone_off}" : "${nf.md-microphone}") : osd_label == "muted" ? "${nf.md-volume_off}" : "${nf.seti-audio}"})
              (progress :class "elapsed" :hexpand true :valign "center" :value osd_value)
              (label :class "value" :width 30 :halign "end" :text "''${osd_value}"))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        // The rice's palette (calm_pink): white text on dark grey modules,
        // mid grey keys and labels, a pastel accent. Here the greys are the
        // matugen surfaces without their hue, and the accent is matugen's.
        $fg: ${m.on_surface};
        $bg: grayscale(${m.surface_container_high});
        $bg-alt: lighten(grayscale(${m.outline_variant}), 4%);
        $muted: mix($fg, $bg, 34%);
        $primary: ${m.primary};
        $on-primary: ${m.on_primary};
        $error: ${m.error};
        $material: ${material};

        $standard: cubic-bezier(0.2, 0, 0, 1);
        $fast: 120ms;
        $radius: 10px;
        $edge: 1.5px solid rgba($primary, 0.9);

        * {
          all: unset;
          font-family: "Maple Mono NF CN";
          font-size: 12px;
          color: $fg;
        }

        tooltip {
          background-color: $bg;
          border: $edge;
          border-radius: 8px;
          padding: 4px 10px;
        }
        tooltip label {
          font-weight: bold;
        }

        // Nerd glyphs are wider than the monospace cell they sit in, so each
        // gets a box its own size.
        .glyph {
          font-size: 14px;
          min-width: 18px;
        }
        .accent {
          color: $primary;
        }
        .value {
          font-weight: bold;
        }
        .dim {
          color: $muted;
        }
        .caption {
          color: $muted;
          font-size: 11px;
        }

        // The strip: light and translucent, framing the dark modules.
        .strip {
          background-color: rgba($fg, 0.5);
        }
        .half {
          margin: ${toString margin}px ${toString gap}px 0;
        }
        .module {
          background-color: rgba($bg, $material);
          border: $edge;
          border-radius: $radius;
          padding: 0 14px;
          transition: background-color $fast $standard;
        }
        .hit:hover > .module {
          background-color: mix($fg, $bg, 6%);
        }
        .module.open {
          background-color: mix($fg, $bg, 10%);
        }
        .launcher {
          padding: 0;
        }
        .launcher-glyph {
          font-size: 16px;
        }

        // The notch, dressed as a module: flush with the top edge, a chin of
        // dark below the hardware, and the accent edge down both sides.
        .notch {
          background-color: $bg;
          border: $edge;
          border-top: none;
          border-radius: 0 0 14px 14px;
        }

        .ws {
          font-size: 16px;
          transition: color $fast $standard;
        }
        .ws.active,
        .ws.occupied {
          color: $primary;
        }
        .ws.empty {
          color: $fg;
          font-size: 12px;
        }
        .tag:hover .ws {
          color: mix($primary, $fg, 50%);
        }

        .music {
          padding: 0;
        }
        .music-wash {
          background-size: cover;
          background-position: center;
          border-radius: $radius;
          opacity: 0.3;
        }
        .thumb {
          margin-left: 4px;
          background-size: cover;
          background-position: center;
          border-radius: 7px;
        }
        .line {
          font-size: 10px;
          font-weight: bold;
        }

        .heart {
          color: $primary;
          font-size: 14px;
          min-width: 14px;
        }
        .hearts.low .heart {
          color: $error;
        }

        .scrim {
          background-color: transparent;
        }

        // Panels and their keys.
        .panel {
          background-color: rgba($bg, $material);
          border: $edge;
          border-radius: 16px;
          padding: 18px;
        }
        .key {
          background-color: $bg-alt;
          border-radius: $radius;
          transition: background-color $fast $standard;
        }
        .hit:hover > .key {
          background-color: mix($fg, $bg-alt, 10%);
        }
        .key.lit {
          background-color: mix($primary, $bg, 45%);
        }
        .key.armed {
          background-color: $primary;
        }
        .key.armed .glyph {
          color: $on-primary;
        }

        .big-clock {
          font-size: 36px;
          font-weight: bold;
          color: mix($primary, $fg, 22%);
          margin: 6px 0 4px;
        }
        .dateline {
          margin-bottom: 16px;
        }
        .profile {
          border: 1.5px solid $bg-alt;
          border-radius: 16px;
          padding: 16px 0 14px;
          margin-bottom: 16px;
        }
        .portrait {
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
          border-radius: 50%;
        }
        .name {
          font-size: 17px;
          font-weight: bold;
        }

        .meter {
          margin-bottom: 12px;
        }
        .meter-glyph {
          font-size: 13px;
          min-width: 14px;
        }
        scale.bar {
          margin: 2px 0;
        }
        scale.bar trough,
        progressbar trough {
          min-height: 6px;
          border-radius: 99px;
          background-color: mix(#000000, $bg, 25%);
          border: 1px solid $bg-alt;
        }
        scale.bar highlight,
        progressbar progress {
          min-height: 6px;
          border-radius: 99px;
          background-color: $primary;
        }
        scale.bar slider {
          min-width: 12px;
          min-height: 12px;
          margin: -4px 0;
          border-radius: 50%;
          background-color: $fg;
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

        .connection {
          margin-top: 6px;
        }
        .connection + .connection {
          margin-top: 14px;
        }
        .pill.off .value {
          color: $muted;
        }

        .stage {
          border-radius: 16px;
          border: 1.5px solid $bg-alt;
          margin-bottom: 16px;
        }
        .stage-ground {
          border-radius: 15px;
          background-color: mix(#000000, $bg, 30%);
        }
        .cover {
          background-size: cover;
          background-position: center;
          background-color: $bg-alt;
          border-radius: 4px;
          box-shadow: 0 0 18px 2px rgba(#ffffff, 0.35);
        }
        .cover-glyph {
          font-size: 40px;
        }
        .controls {
          margin-bottom: 14px;
        }
        .track {
          font-size: 12px;
        }
        .elapsed {
          margin-top: 12px;
        }

        .column {
          padding: 12px;
        }

        .osd.muted progressbar progress {
          background-color: $bg-alt;
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

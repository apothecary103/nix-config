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

  # Nerd Font glyphs by name, as Maple Mono NF carries them.
  nerdMap =
    pkgs:
    let
      names = builtins.fromJSON (builtins.readFile "${pkgs.nerd-font-patcher}/share/glyphnames.json");
      hex = n: lib.toLower (lib.fixedWidthString 4 "0" (lib.toHexString n));
      char =
        code:
        builtins.fromJSON (
          if code < 65536 then
            ''"\u${hex code}"''
          else
            let
              c = code - 65536;
            in
            ''"\u${hex (55296 + c / 1024)}\u${hex (56320 + lib.mod c 1024)}"''
        );
    in
    lib.mapAttrs (_: g: char (lib.fromHexString g.code)) (
      lib.filterAttrs (_: g: lib.isAttrs g && g ? code) names
    );
in
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      fonts.packages = [ pkgs.lucide ];
    };

  # The desktop shell, in eww. The bar is the river rice's yambar again: flat
  # text on one plain strip, filling the 37 rows Asahi gives back beside the
  # notch (show_notch=1) and black like it, so the notch disappears. The
  # avatar, kanji workspaces from 零 and the focused app on the left; the
  # track, network, volume, battery and the clock on the right. The avatar
  # opens a panel after Tail-R's xmonad rice (a big clock, a profile card,
  # the power keys); the status and time open the controls, the track the
  # player. Maple Mono with Lucide icons, in the sakura theme.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      icon = lucideMap pkgs;
      nf = nerdMap pkgs;
      eww = lib.getExe pkgs.eww;

      band = 37;
      # The notch is 74 rows deep (the device tree's apple,notch-height), 37
      # at 2x, the height macOS gives this MacBook's menu bar; about 185 wide,
      # kept clear with some room either side. The panel's top corners are
      # rounded, so the bar keeps 16 in from its ends.
      notchZone = 200;
      inset = 16;
      edge = 10;
      gap = 6;

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

      # The default route's interface every two seconds: whether bytes came in
      # or went out since the last look (a liveness hint, not a rate, as the
      # quickshell bar had it), and its Wi-Fi link quality out of 100.
      traffic =
        script "shell-traffic"
          [
            pkgs.coreutils
            pkgs.gawk
            pkgs.iproute2
          ]
          ''
            last_iface="" last_rx=-1 last_tx=-1
            while :; do
              iface=$(ip route show default 2>/dev/null | awk '{ print $5; exit }')
              rx=-1 tx=-1 signal=0 receiving=false transmitting=false
              if [ -n "$iface" ] && [ -r "/sys/class/net/$iface/statistics/rx_bytes" ]; then
                rx=$(< "/sys/class/net/$iface/statistics/rx_bytes")
                tx=$(< "/sys/class/net/$iface/statistics/tx_bytes")
                signal=$(awk -v i="$iface:" '$1 == i { q = $3; sub(/\.$/, "", q); print int(q * 100 / 70) }' /proc/net/wireless)
              fi
              if [ "$iface" = "$last_iface" ] && [ "$last_rx" -ge 0 ]; then
                [ $((rx - last_rx)) -gt 1024 ] && receiving=true
                [ $((tx - last_tx)) -gt 1024 ] && transmitting=true
              fi
              printf '{"rx":%s,"tx":%s,"signal":%s}\n' "$receiving" "$transmitting" "''${signal:-0}"
              last_iface=$iface last_rx=$rx last_tx=$tx
              sleep 2
            done
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

      # The time once a minute, on the minute.
      clock = script "shell-clock" [ pkgs.coreutils ] ''
        while :; do
          date '+{"hour":"%H","minute":"%M","weekday":"%A","date":"%-d, %B","bar":"%a %-d %b  %H:%M"}'
          sleep $((60 - 10#$(date +%S)))
        done
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

      # The bar, once the daemon answers and river has a monitor for it, for up
      # to ten seconds.
      open = script "shell-open" [ pkgs.coreutils pkgs.eww ] ''
        for _ in $(seq 100); do
          eww ping >/dev/null 2>&1 && eww open bar >/dev/null 2>&1 && exit 0
          sleep 0.1
        done
        exit 1
      '';

      art = ''{media.art != "" ? "background-image: url('" + media.art + "');" : ""}'';

      # Workspaces in kanji, counting from nought: 零, not the ring 〇.
      numerals = builtins.toJSON [
        "零"
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
        (deflisten traffic :initial '{"rx":false,"tx":false,"signal":0}' "${traffic}")
        (deflisten media :initial '{"status":"","title":"","artist":"","art":"","tint":"","length":0,"player":""}' "${media}")
        (defpoll bluetooth :interval "5s" :initial '{"powered":false,"device":""}' "${bluetooth}")
        (deflisten clock :initial '{"hour":"","minute":"","weekday":"","date":"","bar":""}' "${clock}")
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

        ; A key in a panel.
        (defwidget key [?class ?width height onclick ?tooltip]
          (eventbox :class "hit" :onclick onclick :cursor "pointer" :tooltip tooltip
            (box :class "key ''${class}" :width {width == "" ? 0 : width} :height height
              (children))))

        ; A panel dropped from the strip.
        (defwidget panel [?class]
          (box :class "panel ''${class}" :orientation "v" :space-evenly false
            (children)))
      '';

      xdg.config.files."eww/bar.yuck".text = ''
        ; The quickshell bar on main (quickshell/qml/bar), its pills made one
        ; mantle strip for this MacBook: as tall as the notch (${toString band}),
        ; flush with the top, its two halves either side of the notch with
        ; nothing under it, ${toString inset} in from the panel's rounded corners.
        ; Left: the avatar, the workspaces in kanji from 零 (five always), the
        ; track; right: the tray behind a chevron, the network with its
        ; traffic arrows, the volume, the battery drawn as a cell, the clock.
        (defwidget separator [?visible]
          (box :class "separator" :valign "center" :width 1 :height 14
               :visible {visible == "" ? true : visible}))

        (defwidget kwm-tag [tag]
          (eventbox
            :visible {tag.focused || tag.occupied || tag.id <= 5}
            :cursor "pointer"
            :onclick "echo set_output_tag ''${tag.id} > $XDG_RUNTIME_DIR/kwm/control"
            (label :class {tag.focused ? "numeral active" : "numeral"} :text {numerals[tag.id - 1]})))

        (defvar tray_expanded false)

        (defwindow bar
          :monitor 0
          :stacking "fg"
          :exclusive true
          :focusable "none"
          :namespace "bar"
          :geometry (geometry :x "0" :y "0" :width "100%" :height "${toString band}px" :anchor "top center")
          (centerbox :class "strip"
            (box :class "side left" :halign "start" :space-evenly false :spacing 10
              (box :class "avatar" :valign "center" :width 20 :height 20)
              ; Its own box: eww appends a for's children after their siblings.
              (box :space-evenly false :spacing 12 :valign "center"
                (for tag in {kwm.tags}
                  (kwm-tag :tag tag)))
              (separator :visible {media.title != ""})
              (box :class "now-playing" :space-evenly false :spacing 8 :valign "center"
                   :visible {media.title != ""}
                (box :class "art" :width 20 :height 20 :valign "center" :style ${art}
                  (label :class "art-note" :hexpand true :visible {media.art == ""} :text "${nf.fa-music}"))
                (box :space-evenly false :spacing 6
                  (label :class "track" :limit-width 18 :text {media.title != "" ? media.title : "Unknown"})
                  (label :class "dot" :visible {media.artist != ""} :text "·")
                  (label :class "artist" :limit-width 13 :visible {media.artist != ""} :text {media.artist}))
                (eventbox :cursor "pointer" :onclick "playerctl play-pause" :width 16
                  (label :class "play" :text {media.status == "Playing" ? "${nf.fa-pause}" : "${nf.fa-play}"}))))
            ; Nothing under the notch.
            (box :class "notch" :width ${toString notchZone})
            (box :class "side right" :halign "end" :space-evenly false :spacing 12
              (box :space-evenly false :spacing 6 :valign "center"
                (eventbox :cursor "pointer" :onclick "eww update tray_expanded=''${!tray_expanded}"
                  (label :class {tray_expanded ? "chevron expanded" : "chevron"} :text "${nf.md-chevron_left}"))
                (revealer :reveal tray_expanded :transition "slideleft" :duration "250ms"
                  (systray :class "tray" :icon-size 16 :spacing 8 :prepend-new true)))
              (separator)
              (box :class "network" :space-evenly false :valign "center"
                (label :class {network.kind == "none" ? "wifi off" : "wifi"}
                       :text {network.kind == "none" ? "${nf.md-wifi_strength_outline}"
                         : network.kind == "wired" || traffic.signal > 75 ? "${nf.md-wifi_strength_4}"
                         : traffic.signal > 50 ? "${nf.md-wifi_strength_3}"
                         : traffic.signal > 25 ? "${nf.md-wifi_strength_2}" : "${nf.md-wifi_strength_1}"})
                (box :class "arrows" :orientation "v" :valign "center" :width 7 :visible {network.kind != "none"}
                  (label :class {traffic.tx ? "arrow on" : "arrow"} :text "▴")
                  (label :class {traffic.rx ? "arrow on" : "arrow"} :text "▾")))
              (eventbox :cursor "pointer" :onclick "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
                        :onscroll "osd volume-{}" :valign "center"
                (box :class {volume.muted ? "volume muted" : "volume"} :space-evenly false :spacing 6
                  (label :class "volume-icon"
                         :text {volume.muted ? "${nf.fa-volume_off}" : volume.level >= 50 ? "${nf.fa-volume_up}" : "${nf.fa-volume_down}"})
                  (label :class "value" :text {volume.muted ? "Mute" : "''${volume.level}%"})))
              (box :class {${bat}.status == "Charging" ? "battery charging" : ${bat}.capacity < 20 ? "battery low" : "battery"}
                   :space-evenly false :spacing 6 :valign "center"
                (box :space-evenly false :valign "center" :width 23 :height 12
                  ; GTK overlays draw no border, so the cell's outline is a box around it.
                  (box :class "cell" :width 20 :height 12
                    (overlay :hexpand true
                      (box :space-evenly false
                        (box :class "fill" :width {max(2, round(16 * ${bat}.capacity / 100, 0))}))
                      (label :class "bolt" :visible {${bat}.status == "Charging"} :text "${nf.md-lightning_bolt}")))
                  (box :class "tip" :valign "center" :width 3 :height 6))
                (label :class "value" :text "''${${bat}.capacity}%"))
              (separator)
              (label :class "clock" :valign "center" :text {clock.bar}))))

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
        ; From the track, at the right like the controls.
        (defwindow player
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "popover"
          :geometry (geometry :x "${toString edge}px" :y "${toString gap}px" :width "300px" :anchor "top right")
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
        (defvar osd_label "volume")
        (defvar osd_open false)

        ; As the lambda branch drew it: a card low in the middle, where macOS
        ; has long put it, the word and the level over a thin bar; here in
        ; Catppuccin and Maple Mono, rounded like the bar's tooltips. Not
        ; interactive.
        (defwindow osd
          :monitor 0
          :stacking "overlay"
          :exclusive false
          :focusable "none"
          :namespace "osd"
          :geometry (geometry :x "0" :y "96px" :width "280px" :anchor "bottom center")
          (box :class {matches(osd_label, "muted$") ? "osd-card muted" : "osd-card"}
               :orientation "v" :space-evenly false
            (box :space-evenly false
              (label :class "osd-label" :halign "start" :hexpand true :text {osd_label})
              (label :class "osd-value" :halign "end" :text "''${osd_value}%"))
            (box :class "osd-level" :width 244 :height 6 :space-evenly false
              (box :class "osd-fill" :width {round(osd_value * 2.44, 0)}))))
      '';

      xdg.config.files."eww/eww.scss".text = ''
        // Catppuccin Macchiato (see theme.nix), in the accent the wallpaper suggests.
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
          border-radius: 7px;
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

        // The quickshell bar's Theme, as one strip: Maple Mono on Catppuccin's
        // mantle, a touch clear over river's blur.
        // Its blue highlights take the accent the wallpaper suggests (theme.nix).
        // Nerd glyphs are wider than the monospace cell they sit in, so each icon
        // gets a box its own size, as the quickshell bar gave them Items.
        .strip {
          background-color: rgba(${palette.native.mantle}, 0.9);
        }
        .side {
          padding: 0 ${toString inset}px;
        }
        .strip label {
          font-family: "Maple Mono NF CN";
          font-size: 12px;
          color: ${palette.native.text};
        }
        .separator {
          background-color: ${palette.native.surface1};
        }
        .avatar {
          border-radius: 10px;
          background-color: ${palette.native.surface0};
          background-image: url("${../../../assets/avatar.jpg}");
          background-size: cover;
          background-position: center;
        }
        .strip .numeral {
          font-size: 13px;
          font-weight: bold;
          color: ${palette.native.overlay0};
        }
        .strip .numeral.active {
          color: $accent;
        }
        .art {
          border-radius: 6px;
          background-color: ${palette.native.surface0};
          background-size: cover;
          background-position: center;
        }
        .strip .art-note {
          font-size: 11px;
          min-width: 20px;
          color: ${palette.native.overlay0};
        }
        .strip .track {
          font-weight: 600;
        }
        .strip .dot {
          color: ${palette.native.overlay0};
        }
        .strip .artist {
          font-size: 11px;
          font-style: italic;
          font-weight: 500;
          color: ${palette.native.subtext0};
        }
        .strip .play {
          font-size: 13px;
          min-width: 16px;
          color: $accent;
        }
        .strip .chevron {
          font-size: 16px;
          min-width: 16px;
          color: ${palette.native.subtext0};
          transition: color 200ms;
        }
        .strip .chevron.expanded {
          color: ${palette.native.text};
          -gtk-icon-transform: rotate(180deg);
        }
        .strip .wifi {
          font-size: 18px;
          min-width: 22px;
        }
        .strip .wifi.off {
          color: ${palette.native.overlay0};
        }
        .strip .arrow {
          font-family: sans-serif;
          font-size: 8px;
          min-height: 7px;
          margin: -1px 0;
          color: ${palette.native.surface1};
        }
        .strip .arrow.on {
          color: ${palette.native.text};
        }
        .strip .volume-icon {
          font-size: 15px;
          min-width: 18px;
        }
        .strip .value {
          font-weight: 600;
        }
        .strip .volume.muted label {
          color: ${palette.native.overlay0};
        }
        .cell {
          border: 1px solid ${palette.native.subtext0};
          border-radius: 3px;
        }
        .fill {
          margin: 2px;
          border-radius: 1px;
          background-color: ${palette.native.text};
        }
        .battery.low .fill {
          background-color: ${palette.native.red};
        }
        .battery.charging .fill {
          background-color: ${palette.native.green};
        }
        .strip .bolt {
          font-size: 9px;
          color: ${palette.native.mantle};
        }
        .tip {
          border-radius: 1.5px;
          background-color: ${palette.native.subtext0};
        }
        .strip .clock {
          font-weight: 600;
          letter-spacing: 0.4px;
        }

        .scrim {
          background-color: transparent;
        }

        // Panels: lifted greys over river's blur, a hairline, rounded corners.
        .panel {
          background-color: rgba($raised, 0.75);
          border: $hairline;
          border-radius: 12px;
          padding: 16px;
        }
        // Groups inside a panel sit on the panel itself, parted by space.
        .card {
          border-top: $hairline;
        }
        .key {
          background-color: $key;
          border-radius: 8px;
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
          padding: 0 4px;
        }
        .key.tile {
          background-color: transparent;
        }
        .hit:hover > .key.tile {
          background-color: rgba($text, 0.05);
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
          padding: 16px 2px 0;
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
          border-radius: 8px;
          background-color: $well;
        }
        .cover {
          background-size: cover;
          background-position: center;
          background-color: $key;
          border-radius: 6px;
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

        // The overlay: the lambda card in Catppuccin's mantle, over river's blur.
        .osd-card {
          padding: 14px 18px;
          border-radius: 7px;
          background-color: rgba(${palette.native.mantle}, 0.92);
        }
        .osd-card label {
          font-family: "Maple Mono NF CN";
          font-size: 15px;
          font-weight: 600;
          color: ${palette.native.text};
        }
        .osd-card .osd-value {
          color: ${palette.native.overlay1};
        }
        .osd-level {
          margin-top: 10px;
          min-height: 6px;
          border-radius: 99px;
          background-color: ${palette.native.surface0};
        }
        .osd-fill {
          min-height: 6px;
          border-radius: 99px;
          background-color: $accent;
        }
        .osd-card.muted .osd-fill {
          background-color: ${palette.native.overlay0};
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

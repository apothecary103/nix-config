{
  flake.modules.nixos.base.services.logind.settings.Login = {
    # F6 (the moon key) reaches Linux as KEY_SLEEP, which logind would treat as
    # "suspend now"; on macOS it is Do Not Disturb, which river binds instead.
    HandleSuspendKey = "ignore";

    # The Touch ID key as on macOS: a press puts the Mac to sleep (locking
    # first, see before-sleep below), and only holding it shuts down.
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
  };

  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      accent,
      ...
    }:
    let
      bare = lib.removePrefix "#";

      # The lock screen in the wallpaper's accent (theme.nix) once the session
      # has worked it out, and in the build's until then: a lock must never
      # wait on it.
      live = "${accent.state}/swaylock.conf";
      swaylock = toString (
        pkgs.writeShellScript "lock" ''
          if [ -r ${live} ]; then
            exec ${lib.getExe pkgs.swaylock} -f -C ${live}
          fi
          exec ${lib.getExe pkgs.swaylock} -f
        ''
      );

      # The river rice's lock screen: its own wallpaper behind a Dawn ring.
      lockscreen = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/CelestialCrafter/dotfiles/9091d63a0dd389fc5aa74eb08d833f93027e3199/assets/wallpapers/lockscreen.png";
        hash = "sha256-nsnrEYfg4wGZVaFmU8z8LOjjURAQqskAYPGk7SWAIIw=";
      };
      swaylockConfig =
        hl:
        ''
          font=Maple Mono NF CN
          font-size=18
          indicator-radius=65
          indicator-thickness=16

          color=${bare palette.surface.background}
          image=${lockscreen}
          scaling=fill

          inside-color=${bare palette.surface.panel}
          inside-clear-color=${bare palette.surface.panel}
          inside-caps-lock-color=${bare palette.surface.panel}
          inside-ver-color=${bare palette.surface.panel}
          inside-wrong-color=${bare palette.surface.panel}

          ring-color=${bare palette.surface.neutral2}
          ring-clear-color=${bare palette.surface.neutral2}
          ring-caps-lock-color=${bare palette.surface.neutral2}
          ring-ver-color=${bare palette.surface.neutral2}
          ring-wrong-color=${bare palette.surface.neutral2}
          line-color=${bare palette.surface.neutral2}
          line-clear-color=${bare palette.surface.neutral2}
          line-caps-lock-color=${bare palette.surface.neutral2}
          line-ver-color=${bare palette.surface.neutral2}
          line-wrong-color=${bare palette.surface.neutral2}
          separator-color=00000000

          key-hl-color=${hl}
          bs-hl-color=${hl}
          caps-lock-key-hl-color=${hl}
          caps-lock-bs-hl-color=${hl}

          text-color=${bare palette.surface.text}
          text-clear-color=${bare palette.surface.text}
          text-caps-lock-color=${bare palette.hue.yellow}
          text-ver-color=${bare palette.hue.aqua}
          text-wrong-color=${bare palette.status.error}
          layout-text-color=${bare palette.surface.text}
        '';

      brightnessctl = lib.getExe pkgs.brightnessctl;
      wlopm = lib.getExe pkgs.wlopm;

      # macOS here sleeps the display after 10 minutes on power and 5 on
      # battery (pmset displaysleep 10 and 5), dimming a few seconds first.
      # swayidle's timeouts are fixed, so both pairs are set and the battery
      # pair looks at the power source when it fires. Whichever dims first
      # leaves a mark, so the other neither halves the screen again nor
      # restores the wrong level.
      #
      # apple-panel-bl counts in nits, so an absolute target would brighten a
      # screen already below it. Halve instead, but stay clear of the 2 nits
      # where the backlight switches off. -s saves the level for -r.
      idle = pkgs.writeShellScript "idle" ''
        marker="''${XDG_RUNTIME_DIR:-/tmp}/idle-dimmed"
        battery() {
          [ "$(cat /sys/class/power_supply/macsmc-battery/status 2>/dev/null)" = Discharging ]
        }
        dim() {
          [ -e "$marker" ] && return 0
          cur=$(${brightnessctl} get)
          ${brightnessctl} -s set $((cur > 6 ? cur / 2 : cur))
          touch "$marker"
        }
        undim() {
          [ -e "$marker" ] || return 0
          ${brightnessctl} -r
          rm -f "$marker"
        }
        # A second swaylock while already locked (Ctrl+Cmd+Q, say) exits 2;
        # the display goes dark all the same.
        off() {
          ${swaylock}
          ${wlopm} --off '*'
        }
        case "$1" in
          battery-dim) ! battery || dim ;;
          battery-off) ! battery || off ;;
          dim) dim ;;
          off) off ;;
          undim) undim ;;
          wake) ${wlopm} --on '*'; undim ;;
          reset) rm -f "$marker" ;;
        esac
      '';
    in
    {
      packages = [ pkgs.swaylock ];

      accent.live.swaylock = {
        path = live;
        template = swaylockConfig "@accent@";
      };

      xdg.config.files."swaylock/config".text = swaylockConfig (bare palette.ui.accent);

      # The display sleeps as on macOS (see idle above), and locks as it goes
      # dark: macOS waits 5 more minutes before asking for the password
      # (screenLock delay 300), which swaylock cannot. Nor does the system
      # sleep with the display, as macOS's sleep 1 has it. Lid close and
      # suspend lock first too (before-sleep).
      systemd.services.swayidle = {
        description = "Idle dim, lock and display sleep";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStartPre = "${idle} reset";
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.swayidle)
            "-w"
            "timeout"
            "290"
            "${idle} battery-dim"
            "resume"
            "${idle} undim"
            "timeout"
            "300"
            "${idle} battery-off"
            "resume"
            "${idle} wake"
            "timeout"
            "590"
            "${idle} dim"
            "resume"
            "${idle} undim"
            "timeout"
            "600"
            "${idle} off"
            "resume"
            "${idle} wake"
            "before-sleep"
            swaylock
            "lock"
            swaylock
          ];
          Restart = "on-failure";
        };
      };
    };
}

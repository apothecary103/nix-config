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

      # apple-panel-bl counts in nits, so an absolute target would brighten a
      # screen already below it. Halve instead, but stay clear of the 2 nits
      # where the backlight switches off. -s saves the level for -r either way.
      dim = pkgs.writeShellScript "dim" ''
        cur=$(${brightnessctl} get)
        ${brightnessctl} -s set $((cur > 6 ? cur / 2 : cur))
      '';
    in
    {
      packages = [ pkgs.swaylock ];

      accent.live.swaylock = {
        path = live;
        template = swaylockConfig "@accent@";
      };

      xdg.config.files."swaylock/config".text = swaylockConfig (bare palette.ui.accent);

      # macOS here: the display sleeps after 10 minutes (pmset displaysleep 10),
      # dimming a few seconds first, and asks for the password as it goes dark.
      # Lid close and suspend lock first too (before-sleep).
      systemd.services.swayidle = {
        description = "Idle dim, lock and display sleep";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.swayidle)
            "-w"
            "timeout"
            "590"
            "${dim}"
            "resume"
            "${brightnessctl} -r"
            "timeout"
            "600"
            "${swaylock} && ${wlopm} --off '*'"
            "resume"
            "${wlopm} --on '*'; ${brightnessctl} -r"
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

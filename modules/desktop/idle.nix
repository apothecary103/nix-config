{
  # F6 (the moon key) reaches Linux as KEY_SLEEP, which logind would treat as
  # "suspend now"; on macOS it is Do Not Disturb, which sway binds instead.
  flake.modules.nixos.base.services.logind.settings.Login.HandleSuspendKey = "ignore";

  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      swaylock = "${lib.getExe pkgs.swaylock} -f -c ${lib.removePrefix "#" palette.surface.background}";
      brightnessctl = lib.getExe pkgs.brightnessctl;
      swaymsg = lib.getExe' pkgs.sway-unwrapped "swaymsg";

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

      # macOS here: the display sleeps after 10 minutes (pmset displaysleep 10),
      # dimming a few seconds first, and asks for the password as it goes dark.
      # Lid close and suspend lock first too (before-sleep).
      systemd.services.swayidle = {
        description = "Idle dim, lock and display sleep";
        wantedBy = [ "sway-session.target" ];
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
            "${swaylock} && ${swaymsg} 'output * power off'"
            "resume"
            "${swaymsg} 'output * power on'; ${brightnessctl} -r"
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

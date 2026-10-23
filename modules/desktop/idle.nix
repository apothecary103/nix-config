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
            "${brightnessctl} -s set 20%"
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

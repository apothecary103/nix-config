{
  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    {
      packages = [
        pkgs.mako
        pkgs.libnotify
      ];

      # Banners as macOS draws them: top right below the menu bar, rounded,
      # gone after five seconds unless they are critical.
      xdg.config.files."mako/config".text = ''
        font=Adwaita Sans 9.75
        anchor=top-right
        margin=12
        padding=12,14
        width=356
        height=160
        border-size=1
        border-radius=16
        icon-location=left
        max-icon-size=40
        default-timeout=5000
        background-color=${palette.surface.panel}f2
        text-color=${palette.surface.text}
        border-color=${palette.surface.neutral1}

        [urgency=critical]
        default-timeout=0
        border-color=${palette.hue.red}

        # F6, the Do Not Disturb key: hide everything but critical alerts.
        [mode=do-not-disturb]
        invisible=1

        [mode=do-not-disturb urgency=critical]
        invisible=0
      '';

      systemd.services.mako = {
        description = "Notification daemon";
        wantedBy = [ "sway-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          ExecStart = lib.getExe pkgs.mako;
          ExecReload = "${lib.getExe' pkgs.mako "makoctl"} reload";
          Restart = "on-failure";
        };
      };
    };
}

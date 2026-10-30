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

      # Banners as the river rice's fnott draws them: square, Overlay with a 2 px
      # border and a coloured title, 13 px apart and in from the corner,
      # gone after five seconds unless they are critical.
      xdg.config.files."mako/config".text = ''
        font=azuki_font 14
        anchor=top-right
        margin=13
        padding=18
        width=356
        height=160
        border-size=2
        border-radius=0
        icon-location=left
        max-icon-size=40
        default-timeout=5000
        max-history=10
        background-color=${palette.surface.panel}
        text-color=${palette.surface.text}
        border-color=${palette.hue.aqua}
        progress-color=over ${palette.surface.textDim}
        format=<span foreground="${palette.hue.aqua}">%s</span>\n%b

        [urgency=low]
        border-color=${palette.surface.neutral2}
        format=<span foreground="${palette.surface.textDim}">%s</span>\n%b

        [urgency=critical]
        default-timeout=0
        border-color=${palette.status.error}
        format=<span foreground="${palette.status.error}">%s</span>\n%b

        # F6, the Do Not Disturb key: hide everything but critical alerts.
        [mode=do-not-disturb]
        invisible=1

        [mode=do-not-disturb urgency=critical]
        invisible=0
      '';

      systemd.services.mako = {
        description = "Notification daemon";
        wantedBy = [ "river-session.target" ];
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

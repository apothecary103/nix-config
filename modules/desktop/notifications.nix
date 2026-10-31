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

      # Banners like the shell's modules (shell/shell.nix): rounded, an accent
      # edge, the title over the body in Maple Mono, on the 4 px grid and in
      # from the corner under the menubar. Gone after five seconds unless critical.
      xdg.config.files."mako/config".text = ''
        font=Maple Mono NF CN 10
        anchor=top-right
        margin=8
        padding=16
        width=344
        height=160
        border-size=2
        border-radius=12
        icon-location=left
        max-icon-size=32
        default-timeout=5000
        max-history=10
        background-color=${palette.surface.neutral0}f2
        text-color=${palette.surface.textMuted}
        border-color=${palette.ui.accent}
        progress-color=over ${palette.surface.neutral2}
        format=<b><span foreground="${palette.surface.text}">%s</span></b>\n%b

        [urgency=low]
        format=<span foreground="${palette.surface.textDim}">%s</span>\n%b

        [urgency=critical]
        default-timeout=0
        border-color=${palette.status.error}
        format=<b><span foreground="${palette.status.error}">%s</span></b>\n%b

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

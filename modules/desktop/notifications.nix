{
  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      m = palette.native;
    in
    {
      packages = [
        pkgs.mako
        pkgs.libnotify
      ];

      # Banners in the shell's material (shell/shell.nix): square, a hairline
      # edge, the title over the body in Maple Mono, on the 4 px grid and in
      # from the corner under the menubar. Gone after five seconds unless critical.
      xdg.config.files."mako/config".text = ''
        font=Maple Mono NF CN 10
        anchor=top-right
        margin=8
        padding=16
        width=344
        height=160
        border-size=1
        border-radius=0
        icon-location=left
        max-icon-size=32
        default-timeout=5000
        max-history=10
        background-color=${m.surface_container}e0
        text-color=${m.on_surface_variant}
        border-color=${m.outline_variant}
        progress-color=over ${m.surface_container_highest}
        format=<b><span foreground="${m.on_surface}">%s</span></b>\n%b

        [urgency=low]
        format=<span foreground="${m.on_surface_variant}">%s</span>\n%b

        [urgency=critical]
        default-timeout=0
        border-color=${m.error}
        format=<b><span foreground="${m.error}">%s</span></b>\n%b

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

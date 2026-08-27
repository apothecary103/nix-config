{
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      programs.dconf = {
        enable = true;

        # hjem has no activation hook to run `dconf load`, so the keys ship as a
        # system database in the user profile rather than being written into
        # ~/.config/dconf/user. They stay overridable from the UI.
        profiles.user.databases = [
          {
            settings."org/gnome/desktop/interface" = {
              color-scheme = "prefer-dark";
              icon-theme = "Adwaita";
              cursor-theme = "WhiteSur-cursors";
              # The schema types this `i`, which a bare Nix int is ambiguous for.
              cursor-size = lib.gvariant.mkInt32 24;
              font-name = "Adwaita Sans Medium 11";
              monospace-font-name = "Maple Mono NF CN 11";
            };
          }
        ];
      };

      # libadwaita apps decide light/dark from the xdg-desktop-portal Settings
      # backend, not from GTK settings. niri defaults that to gnome, whose impl
      # needs gnome-settings-daemon (absent in a bare niri session), so the query
      # returns nothing and the apps fall back to light. The gtk backend reads
      # `color-scheme` (set above) straight from GSettings.
      xdg.portal = {
        config.niri."org.freedesktop.impl.portal.Settings" = "gtk";

        extraPortals = [
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-gnome
        ];
      };
    };

  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      rum.misc.gtk = {
        enable = true;

        packages = [
          pkgs.adwaita-icon-theme
          # Match the compositor's WhiteSur cursor so GTK apps don't flip to the
          # default X cursor on hover.
          pkgs.whitesur-cursors
        ];

        settings = {
          # Medium because the Regular cut renders too thin on a hinting-off
          # Retina panel — see fontconfig.nix for the global rule.
          font-name = "Adwaita Sans Medium 11";

          icon-theme-name = "Adwaita";
          cursor-theme-name = "WhiteSur-cursors";
          cursor-theme-size = 24;

          # Keep GTK's own XSETTINGS in step with fontconfig.nix, so GTK apps
          # don't render text differently from everything else.
          application-prefer-dark-theme = 1;
          xft-antialias = 1;
          xft-hinting = 0;
          xft-hintstyle = "hintnone";
          xft-rgba = "none";
        };
      };
    };
}

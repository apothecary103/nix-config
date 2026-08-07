{ ... }: {
  flake.modules.nixos.base = {
    # Needed so home-manager can write the dconf keys below.
    programs.dconf.enable = true;

    # libadwaita apps decide light/dark from the xdg-desktop-portal Settings
    # backend, not from GTK settings. niri defaults that to gnome, whose impl
    # needs gnome-settings-daemon (absent in a bare niri session), so the query
    # returns nothing and the apps fall back to light. The gtk backend reads
    # `color-scheme` (set below) straight from GSettings.
    xdg.portal.config.niri."org.freedesktop.impl.portal.Settings" = "gtk";
  };

  flake.modules.homeManager.linux = { pkgs, ... }: {
    # The Settings=gtk pin above needs the frontend to find the gtk backend's
    # `.portal` file. The home-manager Hyprland module enables home-manager's
    # xdg.portal, which repoints NIX_XDG_DESKTOP_PORTAL_DIR at the user
    # profile's portals dir — and that dir held only hyprland.portal, so under
    # niri the frontend saw no Settings interface at all. gnome also restores
    # niri's screencast portal, collateral of the same issue.
    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        icon-theme = "Adwaita";
        cursor-theme = "WhiteSur-cursors";
        cursor-size = 24;
        font-name = "Adwaita Sans Medium 11";
        monospace-font-name = "Maple Mono NF CN 11";
      };
    };

    gtk = {
      enable = true;

      # Medium because the Regular cut renders too thin on a hinting-off Retina
      # panel — see fontconfig.nix for the global rule.
      font = {
        name = "Adwaita Sans Medium";
        size = 11;
      };

      # Without this Nautilus falls back to bare hicolor and most
      # mimetype/places icons don't render.
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };

      # Match the compositor's WhiteSur cursor so GTK apps don't flip to the
      # default X cursor on hover.
      cursorTheme = {
        name = "WhiteSur-cursors";
        package = pkgs.whitesur-cursors;
        size = 24;
      };

      gtk4.theme = null;

      # Keep GTK's own XSETTINGS in step with fontconfig.nix, so GTK apps don't
      # render text differently from everything else.
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-xft-antialias = 1;
        gtk-xft-hinting = 0;
        gtk-xft-hintstyle = "hintnone";
        gtk-xft-rgba = "none";
      };
    };
  };
}

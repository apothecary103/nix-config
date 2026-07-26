{ ... }: {
  flake.modules.nixos.base = {
    # Needed so home-manager can write the dconf keys below.
    programs.dconf.enable = true;

    # libadwaita apps (Nautilus, Loupe) decide light/dark from the
    # xdg-desktop-portal Settings backend, not from GTK settings. niri defaults
    # that backend to gnome, whose Settings impl needs gnome-settings-daemon
    # (absent in a bare niri session) — so the appearance query returns nothing
    # and the apps fall back to light. Pin it to the gtk backend, which reads
    # `color-scheme` (prefer-dark, set below) straight from GSettings.
    xdg.portal.config.niri."org.freedesktop.impl.portal.Settings" = "gtk";
  };

  flake.modules.homeManager.linux = { pkgs, ... }: {
    # The Settings=gtk pin above only takes effect if the portal frontend can
    # actually find the gtk backend's `.portal` file. The home-manager Hyprland
    # module enables home-manager's own xdg.portal (its portalPackage defaults
    # to xdg-desktop-portal-hyprland), which repoints NIX_XDG_DESKTOP_PORTAL_DIR
    # at the *user* profile's portals dir — and that dir shipped only
    # hyprland.portal. So under niri the frontend saw no gtk/gnome backend at
    # all: no Settings interface, and libadwaita fell back to light. Adding the
    # gtk and gnome backends here populates that same user-profile dir, so the
    # gtk Settings backend (which reports color-scheme=prefer-dark from the
    # dconf key below) is found and Nautilus/Loupe honour dark mode. gnome also
    # restores niri's screencast portal, which was collateral of the same issue.
    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        # Keep GNOME/libadwaita apps (Nautilus, Loupe) in step with the GTK
        # icon and cursor themes set below, so nothing falls back to a
        # half-populated default.
        icon-theme = "Adwaita";
        cursor-theme = "WhiteSur-cursors";
        cursor-size = 24;
        font-name = "Adwaita Sans Medium 11";
        monospace-font-name = "Maple Mono NF CN 11";
      };
    };

    gtk = {
      enable = true;

      # Adwaita Sans (GNOME 48's Inter-based UI face) for GTK app chrome — the
      # same face macOS approximates with San Francisco, tuned for HiDPI.
      # Medium weight: on a hinting-off Retina panel the Regular cut renders
      # too thin next to macOS's smoothed text, so the whole desktop chrome
      # is pinned one step heavier (see fontconfig.nix for the global rule).
      font = {
        name = "Adwaita Sans Medium";
        size = 11;
      };

      # GNOME's stock icon set. Without this, Nautilus falls back to the bare
      # hicolor theme and most mimetype/places icons simply don't render;
      # morewaita (installed alongside) fills in extra app icons in the same
      # Adwaita style. Symbolic icons for libadwaita apps live here too.
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

      # Let Home Manager automatically handle GTK4 theme alignment
      gtk4.theme = null;

      # Keep GTK's own XSETTINGS in step with the fontconfig rendering choice
      # (no hinting, grayscale AA) so GTK apps don't render text differently
      # from everything else.
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

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
              # macOS sets UI text at 13 pt, and a macOS point is a logical pixel;
              # at 96 dpi, 9.75 pt is that same 13 px (11 pt would be 14.7).
              font-name = "Adwaita Sans 9.75";
              monospace-font-name = "Maple Mono NF CN 11";
              # What GTK3 on Wayland actually reads for rendering (its own
              # fallback without the schema is medium hinting, which skips the
              # autofitter's stem darkening). GTK4's automatic font rendering
              # already uses slight, grayscale and unhinted metrics.
              font-hinting = "slight";
              font-antialiasing = "grayscale";
            };
          }
        ];
      };

      # libadwaita apps decide light/dark from the xdg-desktop-portal Settings
      # backend, not from GTK settings. The gtk backend reads `color-scheme` (set
      # above) straight from GSettings; sway.nix points the portal at it.
      xdg.portal = {
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
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
          font-name = "Adwaita Sans 9.75";

          icon-theme-name = "Adwaita";
          cursor-theme-name = "WhiteSur-cursors";
          cursor-theme-size = 24;

          # In step with fontconfig.nix for GTK3 under X11. On Wayland GTK3
          # takes these from the dconf keys above and GTK4 ignores them.
          application-prefer-dark-theme = 1;
          xft-antialias = 1;
          xft-hinting = 1;
          xft-hintstyle = "hintslight";
          xft-rgba = "none";
        };
      };
    };
}

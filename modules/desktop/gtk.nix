{
  # Needed so home-manager can write the dconf keys below.
  flake.modules.nixos.base.programs.dconf.enable = true;

  flake.modules.homeManager.linux = {
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };

    gtk = {
      enable = true;

      # A proportional humanist sans (SF-adjacent, and OTF so stem-darkening
      # fattens it) for GTK app chrome — closer to the macOS UI feel than
      # falling back to a thin default sans.
      font = {
        name = "Source Sans 3";
        size = 11;
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

    # qt = {
    #   enable = true;
    #   platformTheme.name = "kvantum";
    #   style.name = "kvantum";
    # };
  };
}

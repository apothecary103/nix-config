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

      # Let Home Manager automatically handle GTK4 theme alignment
      gtk4.theme = null;

      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    };

    # qt = {
    #   enable = true;
    #   platformTheme.name = "kvantum";
    #   style.name = "kvantum";
    # };
  };
}

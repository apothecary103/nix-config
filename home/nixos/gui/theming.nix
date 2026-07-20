{ ... }:

{
  # 1. Modern GSettings / Libadwaita & Flatpak
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  # 2. GTK 2/3/4 Themes
  gtk = {
    enable = true;

    # Let Home Manager automatically handle GTK4 theme alignment
    gtk4.theme = null;

    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  # 3. Qt
  # qt = {
  #   enable = true;
  #   platformTheme.name = "kvantum";
  #   style.name = "kvantum";
  # };
}

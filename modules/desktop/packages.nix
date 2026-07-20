{
  flake.modules.homeManager.linux = {pkgs, ...}: {
    home.packages = with pkgs; [
      awww
      brightnessctl
      wf-recorder
      tuigreet
      grim
      slurp
      fuzzel
      hyprsunset
      wl-clipboard
      whitesur-cursors
      mako
      swayosd
      wayfreeze
      eww
      vips

      # GNOME image viewer (replaces Eye of GNOME); default image handler.
      loupe

      # Extra app icons in the Adwaita style — inherits from the Adwaita icon
      # theme so Nautilus/GTK pick up icons GNOME's stock set omits.
      morewaita-icon-theme
    ];
  };
}

{
  flake.modules.homeManager.linux = { pkgs, ... }: {
    home.packages = with pkgs; [
      awww
      wf-recorder
      grim
      slurp
      wl-clipboard
      jq
      whitesur-cursors
      wayfreeze

      loupe

      # Inherits from the Adwaita icon theme, filling in app icons GNOME's
      # stock set omits.
      morewaita-icon-theme
    ];
  };
}

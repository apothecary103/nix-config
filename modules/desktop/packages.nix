{
  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      packages = with pkgs; [
        awww
        wf-recorder
        grim
        slurp
        wl-clipboard
        jq
        whitesur-cursors

        loupe

        # Inherits from the Adwaita icon theme, filling in app icons GNOME's
        # stock set omits.
        morewaita-icon-theme
      ];
    };
}

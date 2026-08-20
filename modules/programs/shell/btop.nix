{
  flake.modules.hjem.base =
    { pkgs, theme, ... }:
    {
      packages = [ pkgs.btop ];

      # btop.conf has no include mechanism, so the port hands back a name rather
      # than writing this itself.
      xdg.config.files."btop/btop.conf".text = ''
        color_theme = "${theme.btop.themeName}"
        theme_background = False
      '';
    };
}

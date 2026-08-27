{
  flake.modules.hjem.base =
    { pkgs, theme, ... }:

    {
      packages = [ pkgs.zellij ];

      # No shell integration: it auto-starts a session from every interactive
      # shell.
      xdg.config.files."zellij/config.kdl".text = ''
        default_layout "compact"
        theme "${theme.zellij.themeName}"
      '';
    };
}

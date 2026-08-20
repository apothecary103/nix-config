{
  # The theme is picked by $BAT_THEME, out of the cache the active port builds
  # (desktop/theme.nix), so nothing here names it.
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      packages = [
        pkgs.bat
        pkgs.bat-extras.batman
        pkgs.bat-extras.batgrep
      ];
    };
}

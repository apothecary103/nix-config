{ freetypeProperties, ... }:
{
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    let
      # azuki is 1024 upem, near enough 1000, which the session's autofitter
      # curve (tuned for 2048, see fontconfig.nix) darkens twice as much as
      # CoreText would; this one gives a 1000 upem face CoreText's
      # min(0.6, 0.0116 * ppem) px. The variable replaces the session's
      # wholesale, so it carries the other drivers' curves too. The D-Bus and
      # systemd units start the binary by path, so they move with it.
      ghostty = pkgs.symlinkJoin {
        inherit (pkgs.ghostty) name meta;
        paths = [ pkgs.ghostty ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm $out/bin/ghostty
          makeWrapper ${lib.getExe pkgs.ghostty} $out/bin/ghostty \
            --set FREETYPE_PROPERTIES ${lib.escapeShellArg (freetypeProperties "500,181,4850,181,5970,147,9330,94")}
          for unit in dbus-1/services/com.mitchellh.ghostty.service systemd/user/app-com.mitchellh.ghostty.service; do
            rm $out/share/$unit
            substitute ${pkgs.ghostty}/share/$unit $out/share/$unit \
              --replace-fail ${lib.getExe pkgs.ghostty} $out/bin/ghostty
          done
        '';
      };
    in
    {
      rum.programs.ghostty = {
        enable = true;
        package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else ghostty;

        settings = {
          # The river rice's foot: azuki at 14 pt, padded 18 px all round with
          # the slack balanced, a beam cursor, opaque.
          font-family = "azuki_font";
          # Ghostty turns points into pixels at 72 dpi on macOS and 96 on Linux,
          # so this is the same 18.7 logical px on both.
          font-size = if pkgs.stdenv.hostPlatform.isDarwin then 14 * 96 / 72.0 else 14;
          cursor-style = "bar";

          font-thicken = true;
          macos-titlebar-style = "hidden";
          macos-option-as-alt = true;

          window-decoration = "server";
          alpha-blending = "linear";

          window-padding-x = 18;
          window-padding-y = 18;
          window-padding-balance = true;
        };
      };
    };
}

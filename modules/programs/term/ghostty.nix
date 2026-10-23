{ freetypeProperties, ... }:
{
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    let
      # Maple Mono is 1000 upem, which the session's autofitter curve (tuned for
      # 2048, see fontconfig.nix) darkens twice as much as CoreText would; this
      # one gives it CoreText's min(0.6, 0.0116 * ppem) px. The variable replaces
      # the session's wholesale, so it carries the other drivers' curves too. The
      # D-Bus and systemd units start the binary by path, so they move with it.
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
          font-family = "Maple Mono NF CN";
          # Ghostty turns points into pixels at 72 dpi on macOS and 96 on Linux,
          # so 13.5 there is the same 18 logical px as 18 here.
          font-size = if pkgs.stdenv.hostPlatform.isDarwin then 18 else 13.5;

          font-thicken = true;
          macos-titlebar-style = "hidden";
          macos-option-as-alt = true;

          window-decoration = "server";
          alpha-blending = "linear";

          background-opacity = 0.95;
          window-padding-x = 20;
          window-padding-y = 10;
        };
      };
    };
}

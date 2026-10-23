{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      rum.programs.ghostty = {
        enable = true;
        package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

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

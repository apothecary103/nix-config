{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      rum.programs.ghostty = {
        enable = true;
        package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

        settings = {
          font-family = if pkgs.stdenv.isDarwin then "Maple Mono NF CN" else "Maple Mono NF CN Medium";
          font-size = if pkgs.stdenv.isDarwin then 18 else 12;

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

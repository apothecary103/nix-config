{
  flake.modules.homeManager.base = { pkgs, ... }: {
    programs.ghostty = {
      enable = true;
      package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

      settings = {
        theme = if pkgs.stdenv.isDarwin then "Catppuccin Macchiato" else "Catppuccin Mocha";
        font-family = if pkgs.stdenv.isDarwin then "Maple Mono NF CN" else "Maple Mono NF CN Medium";
        font-size = if pkgs.stdenv.isDarwin then 18 else 12;

        # macOS specific tweaks
        font-thicken = true;
        macos-titlebar-style = "hidden";
        macos-option-as-alt = true;

        # Wayland specific tweaks
        window-decoration = "server";
        # window-decoration = "none";
        alpha-blending = "linear";

        background-opacity = 0.93;
        window-padding-x = 20;
        window-padding-y = 10;
      };
    };
  };
}

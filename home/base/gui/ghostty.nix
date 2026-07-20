{ pkgs, ... }: {
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    settings = {
      theme = "Catppuccin Macchiato";
      font-family = "Maple Mono NF CN";
      font-size = if pkgs.stdenv.isDarwin then 18 else 12;

      # macOS specific tweaks
      font-thicken = true;
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;

      # Wayland specific tweaks
      window-decoration = "server";

      # background-opacity = if pkgs.stdenv.isDarwin then 0.93 else 0.98;
      background-opacity = 0.93;
      # background-blur-radius = 50;
      window-padding-x = 20;
      window-padding-y = 10;
    };
  };
}

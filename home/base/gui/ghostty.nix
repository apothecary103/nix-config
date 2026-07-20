{ ... }: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    settings = {
      theme = "Catppuccin Macchiato";
      font-family = "Maple Mono NF CN";
      font-size = 18;

      # macOS specific tweaks
      font-thicken = true;
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;

      background-opacity = 0.93;
      # background-blur-radius = 50;
      window-padding-x = 20;
      window-padding-y = 20;
    };
  };
}

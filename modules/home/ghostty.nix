{
  flake.modules.homeManager.base = {pkgs, ...}: {
    programs.ghostty = {
      enable = true;
      package =
        if pkgs.stdenv.isDarwin
        then pkgs.ghostty-bin
        else pkgs.ghostty;

      settings = {
        theme =
          if pkgs.stdenv.isDarwin
          then "Catppuccin Macchiato"
          else "Catppuccin Mocha";
        font-family =
          if pkgs.stdenv.isDarwin
          then "Maple Mono NF CN"
          else "Maple Mono NF CN Medium";
        font-size =
          if pkgs.stdenv.isDarwin
          then 18
          else 12;

        # macOS specific tweaks
        font-thicken = true;
        macos-titlebar-style = "hidden";
        macos-option-as-alt = true;

        # Wayland specific tweaks
        window-decoration = "server";
        alpha-blending = "linear";

        background-opacity = 0.93;
        window-padding-x = 20;
        window-padding-y = 10;

        # tmux (prefix = Ctrl+a)
        keybind = [
          # Switch tmux windows
          "cmd+digit_1=text:\\x011"
          "cmd+digit_2=text:\\x012"
          "cmd+digit_3=text:\\x013"
          "cmd+digit_4=text:\\x014"
          "cmd+digit_5=text:\\x015"
          "cmd+digit_6=text:\\x016"
          "cmd+digit_7=text:\\x017"
          "cmd+digit_8=text:\\x018"
          "cmd+digit_9=text:\\x019"

          # tmux window management
          "cmd+t=text:\\x01c"
          "cmd+w=text:\\x01&"

          # Navigate tmux windows
          "cmd+left=text:\\x01p"
          "cmd+right=text:\\x01n"

          # Last tmux window
          "cmd+tab=text:\\x01l"
        ];
      };
    };
  };
}

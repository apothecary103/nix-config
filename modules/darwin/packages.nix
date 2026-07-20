{ inputs, pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools

      # GUI Applications
      yabai
      skhd
      sketchybar
      llama-cpp
      opencode
      moonlight-qt
      utm
      aseprite
      inputs.tetro-tui.packages.${system}.default
      # steam
      emacs-unstable
      teamspeak6-client
    ];
  };
}

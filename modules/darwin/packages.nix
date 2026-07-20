{ inputs, pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
      llama-cpp
      qemu
      inputs.tetro-tui.packages.${system}.default

      # GUI Applications
      yabai
      skhd
      sketchybar
      aseprite
      emacs-unstable
      teamspeak6-client
      # steam
      # moonlight-qt
    ];
  };
}

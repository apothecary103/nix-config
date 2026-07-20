{ inputs, pkgs, username, ... }:

let
  teamspeak6-client = pkgs.callPackage ../../pkgs/teamspeak6-client { };
in
{
  home-manager.users.${username} = {
    home.packages =
      (with pkgs; [
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
        mpd
        mpc
        rmpc
      ])
      ++ [
        teamspeak6-client
      ];
  };
}

{ lib, pkgs, username, ... }:

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
        jankyborders
        sketchybar
        llama-cpp
        opencode              
        moonlight-qt
        utm
        # steam
        # emacs-unstable
      ])
      ++ [
        teamspeak6-client
      ];
  };
}

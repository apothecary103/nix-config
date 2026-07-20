{ config, pkgs, ... }:

let
  musicDir = "${config.home.homeDirectory}/Music";
in
{
  home.packages = with pkgs; [
    mpc
    rmpc
  ];

  services.mpd = {
    enable = true;

    musicDirectory = musicDir;

    network = {
      listenAddress = "127.0.0.1";
      port = 6600;
    };

    extraConfig = ''
      auto_update "yes"
      restore_paused "yes"

      audio_output {
        type "osx"
        name "CoreAudio"
        mixer_type "software"
      }
    '';
  };

  launchd.agents.mpd = {
    enable = true;

    config = {
      Label = "org.home-manager.mpd";

      ProgramArguments = [
        "${pkgs.mpd}/bin/mpd"
        "--no-daemon"
        "${config.xdg.configHome}/mpd/mpd.conf"
      ];

      RunAtLoad = true;
      KeepAlive = true;

      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mpd.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mpd.err.log";
    };
  };
}

{
  lib,
  config,
  pkgs,
  ...
}: let
  musicDir = "${config.home.homeDirectory}/Music";
in {
  home.packages = with pkgs; [
    mpc
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

  # Write the generated config to ~/.config/mpd/mpd.conf
  xdg.configFile."mpd/mpd.conf".text = config.services.mpd.generatedConfig;

  # Create data directories for mpd
  home.activation.createMpdDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD mkdir -p "${config.xdg.dataHome}/mpd/playlists"
  '';

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

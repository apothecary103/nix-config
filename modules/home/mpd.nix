{
  # Home-manager's mpd service is systemd-only, so on darwin we reuse its
  # generated config file and run the daemon through our own launchd agent.
  flake.modules.homeManager.darwin = {
    lib,
    config,
    pkgs,
    ...
  }: {
    home.packages = with pkgs; [
      mpc
    ];

    services.mpd = {
      enable = true;

      musicDirectory = "${config.home.homeDirectory}/Music";

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

    xdg.configFile."mpd/mpd.conf".text = config.services.mpd.generatedConfig;

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
  };

  flake.modules.homeManager.linux = {
    config,
    pkgs,
    ...
  }: {
    home.packages = [pkgs.mpc pkgs.playerctl];

    services.mpd = {
      enable = true;
      musicDirectory = "${config.home.homeDirectory}/Music";

      extraConfig = ''
        audio_output {
          type "pipewire"
          name "PipeWire Output"
        }
      '';
    };

    services.mpdris2-rs.enable = true;
  };
}

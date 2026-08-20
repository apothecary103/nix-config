{ username, ... }:
let
  # Everything mpd keeps lives under the XDG data dir, so the same paths work
  # on both hosts; only the audio output and the supervisor differ.
  mkConf =
    { home, output }:
    ''
      music_directory "${home}/Music"
      playlist_directory "${home}/.local/share/mpd/playlists"
      db_file "${home}/.local/share/mpd/tag_cache"
      state_file "${home}/.local/share/mpd/state"
      sticker_file "${home}/.local/share/mpd/sticker.sql"

      bind_to_address "127.0.0.1"
      port "6600"

      auto_update "yes"
      restore_paused "yes"

      ${output}
    '';

  darwinHome = "/Users/${username}";
  darwinConf = mkConf {
    home = darwinHome;
    output = ''
      audio_output {
        type "osx"
        name "CoreAudio"
        mixer_type "software"
      }
    '';
  };
in
{
  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = [ pkgs.mpc ];

      xdg.config.files."mpd/mpd.conf".text = darwinConf;

      # mpd will not create these itself, and hjem has no activation hook.
      xdg.data.files = {
        "mpd/playlists".type = "directory";
      };
    };

  # hjem manages no launchd agents, so the daemon is supervised at the system
  # level; the config file it reads is still the user's.
  flake.modules.darwin.base =
    { pkgs, ... }:
    {
      launchd.user.agents.mpd.serviceConfig = {
        Label = "org.nixos.mpd";

        ProgramArguments = [
          "${pkgs.mpd}/bin/mpd"
          "--no-daemon"
          "${darwinHome}/.config/mpd/mpd.conf"
        ];

        RunAtLoad = true;
        KeepAlive = true;

        StandardOutPath = "${darwinHome}/Library/Logs/mpd.log";
        StandardErrorPath = "${darwinHome}/Library/Logs/mpd.err.log";
      };
    };

  flake.modules.hjem.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      conf = mkConf {
        home = config.directory;
        output = ''
          audio_output {
            type "pipewire"
            name "PipeWire Output"
          }
        '';
      };
    in
    {
      packages = [
        pkgs.mpc
        pkgs.playerctl
      ];

      xdg.config.files."mpd/mpd.conf".text = conf;
      xdg.data.files."mpd/playlists".type = "directory";

      systemd.services = {
        mpd = {
          description = "Music Player Daemon";
          after = [
            "network.target"
            "sound.target"
          ];
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "notify";
            ExecStart = "${lib.getExe pkgs.mpd} --no-daemon ${config.xdg.config.directory}/mpd/mpd.conf";
          };
        };

        # No MPD_HOST/MPD_PORT anywhere: mpdris2-rs mishandles a set MPD_HOST by
        # ignoring MPD_PORT and failing to connect, and every other client here
        # names the address itself.
        mpdris2-rs = {
          description = "MPRIS2 bridge for mpd";
          after = [ "mpd.service" ];
          wantedBy = [ "default.target" ];

          serviceConfig = {
            ExecStart = lib.getExe pkgs.mpdris2-rs;
            Restart = "on-failure";
          };
        };
      };
    };
}

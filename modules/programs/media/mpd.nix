{ username, ... }:
{
  flake.modules.hjem.base =
    { config, pkgs, ... }:
    {
      packages = [
        pkgs.mpc
        pkgs.mpd
      ];

      xdg.config.files."mpd/mpd.conf".text = ''
        music_directory "${config.directory}/Music"
        playlist_directory "${config.directory}/.local/share/mpd/playlists"
        db_file "${config.directory}/.local/share/mpd/tag_cache"
        state_file "${config.directory}/.local/share/mpd/state"
        sticker_file "${config.directory}/.local/share/mpd/sticker.sql"

        bind_to_address "127.0.0.1"
        port "6600"

        ${if pkgs.stdenv.hostPlatform.isLinux then ''auto_update "yes"'' else ""}
        restore_paused "yes"

        audio_output {
          type "${if pkgs.stdenv.hostPlatform.isDarwin then "osx" else "pipewire"}"
          name "${if pkgs.stdenv.hostPlatform.isDarwin then "CoreAudio" else "PipeWire Output"}"
          ${if pkgs.stdenv.hostPlatform.isDarwin then ''mixer_type "software"'' else ""}
        }
      '';

      xdg.data.files."mpd/playlists".type = "directory";
    };

  flake.modules.darwin.base =
    { lib, pkgs, ... }:
    let
      home = "/Users/${username}";
    in
    {
      launchd.user.agents.mpd.serviceConfig = {
        Label = "org.nixos.mpd";

        ProgramArguments = [
          (lib.getExe pkgs.mpd)
          "--no-daemon"
          "--stderr"
          "${home}/.config/mpd/mpd.conf"
        ];

        RunAtLoad = true;
        KeepAlive = true;
      };
    };

  flake.modules.hjem.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      packages = [ pkgs.playerctl ];

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

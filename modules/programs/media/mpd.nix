{ username, ... }:
{
  flake.modules.hjem.base =
    { config, pkgs, ... }:
    let
      output =
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            type = "osx";
            name = "CoreAudio";
          }
        else
          {
            type = "pipewire";
            name = "PipeWire";
          };
    in
    {
      packages = [ pkgs.mpc ];

      xdg.config.files."mpd/mpd.conf".text = ''
        music_directory "${config.directory}/Music"
        playlist_directory "${config.directory}/.local/share/mpd/playlists"
        restore_paused "yes"

        audio_output {
          type "${output.type}"
          name "${output.name}"
        }
      '';

      xdg.data.files."mpd/playlists".type = "directory";
    };

  flake.modules.darwin.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      launchd.user.agents.mpd.serviceConfig = {
        ProgramArguments = [
          (lib.getExe pkgs.mpd)
          "--no-daemon"
          "${config.users.users.${username}.home}/.config/mpd/mpd.conf"
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
          wantedBy = [ "default.target" ];
          serviceConfig.ExecStart = "${lib.getExe pkgs.mpd} --no-daemon ${config.xdg.config.directory}/mpd/mpd.conf";
        };

        mpdris2-rs = {
          wantedBy = [ "default.target" ];
          serviceConfig = {
            ExecStart = lib.getExe pkgs.mpdris2-rs;
            Restart = "on-failure";
          };
        };
      };
    };
}

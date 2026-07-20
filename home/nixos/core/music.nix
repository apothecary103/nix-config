{
  pkgs,
  config,
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
}

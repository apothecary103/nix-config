{ pkgs, config, ... }:

{
  home.packages = [ pkgs.mpc ];

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

  programs.rmpc = {
    enable = true;
  };
}

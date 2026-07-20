{ ... }:

{
  services.swayosd = {
    enable = true;
  };

  xdg.configFile = {
    "swayosd/config.toml".text = ''
      [server]
      ## style file for the OSD
      # style = /etc/xdg/swayosd/style.css

      ## on which height to show the OSD
      top_margin = 0.93

      ## The maximum volume that can be reached in %
      max_volume = 100

      ## show percentage on the right of the OSD
      show_percentage = true

      ## set format for the media player OSD
      playerctl_format = "{artist} - {title}"

      [client]
    '';

    "swayosd/style.css".text = ''
      window#osd {
        background: alpha(#161617, 0.87);
        border-radius: 6px;
      }

      window#osd #container {
        margin: 6px;
        padding: 2px;
        background: transparent;
        border-radius: 6px;
      }

      window#osd image {
        -gtk-icon-transform: scale(0.7);
      }

      window#osd image,
      window#osd label {
        color: #c9c7cd;
        font-family: "MapleMono NF CN", monospace;
      }

      window#osd progressbar:disabled,
      window#osd image:disabled {
        opacity: 0.5;
      }

      window#osd progressbar {
        min-height: 6px;
        border-radius: 6px;
        background: transparent;
        border: none;
      }

      window#osd trough {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: alpha(#252038, 0.5);
      }

      window#osd progress {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: #b9aeda;
      }
    '';
  };
}

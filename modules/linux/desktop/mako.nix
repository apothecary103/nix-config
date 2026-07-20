{
  flake.modules.homeManager.linux = {palette, ...}: {
    services.mako = {
      enable = true;

      settings = {
        font = "MapleMono NF CN 11";
        width = 350;
        height = 150;
        margin = "15";
        padding = "15";

        border-size = 0;
        border-radius = 0;

        icons = true;
        max-icon-size = 48;
        icon-location = "left";

        default-timeout = 5000;
        ignore-timeout = true;
        sort = "-time";

        background-color = "${palette.base}e6";
        text-color = palette.text;
        progress-color = "over ${palette.mauve}";

        "urgency=low" = {
          text-color = palette.green;
          default-timeout = 3000;
        };

        "urgency=normal" = {
          text-color = palette.text;
          default-timeout = 5000;
        };

        "urgency=critical" = {
          background-color = "${palette.base}e6";
          text-color = palette.red;
          default-timeout = 0;
        };
      };
    };
  };
}

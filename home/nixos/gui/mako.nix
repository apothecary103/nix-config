{ ... }:

{
  services.mako = {
    enable = true;

    settings = {
      font = "MapleMono NF CN 11";
      width = 350;
      height = 150;
      margin = "15";
      padding = "15";
      
      border-size = 0;
      border-radius = 4;

      icons = true;
      max-icon-size = 48;
      icon-location = "left";

      default-timeout = 5000;
      ignore-timeout = true;
      sort = "-time";

      background-color = "#161617e6";
      text-color = "#c9c7cd";
      progress-color = "over #e6b99d";

      "urgency=low" = {
        text-color = "#90b99f";
        default-timeout = 3000;
      };

      "urgency=normal" = {
        text-color = "#c9c7cd";
        default-timeout = 5000;
      };

      "urgency=critical" = {
        background-color = "#161617e6";
        text-color = "#f5a191";
        default-timeout = 0;
      };
    };
  };
}

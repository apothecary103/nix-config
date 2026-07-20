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
      border-radius = 0;

      icons = true;
      max-icon-size = 48;
      icon-location = "left";

      default-timeout = 5000;
      ignore-timeout = true;
      sort = "-time";

      background-color = "#24273ae6";
      text-color = "#cad3f5";
      progress-color = "over #c6a0f6";

      "urgency=low" = {
        text-color = "#a6da95";
        default-timeout = 3000;
      };

      "urgency=normal" = {
        text-color = "#cad3f5";
        default-timeout = 5000;
      };

      "urgency=critical" = {
        background-color = "#24273ae6";
        text-color = "#ed8796";
        default-timeout = 0;
      };
    };
  };
}

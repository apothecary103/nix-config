{
  flake.modules.nixos.base = {
    hardware.bluetooth = {
      enable = true;
      settings = {
        General = {
          ControllerMode = "bredr";
        };
      };
    };

    services.blueman.enable = true;
  };
}

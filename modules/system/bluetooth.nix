{
  flake.modules.nixos.base = {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
      settings = {
        General = {
          ControllerMode = "bredr";
        };
      };
    };

    services.blueman.enable = true;
  };
}

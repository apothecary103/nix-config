{
  flake.modules.nixos.base = {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
      settings = {
        General = {
          # Dual mode (BlueZ's default) keeps Bluetooth LE: "bredr" switched it
          # off, which locks out the ZMK keyboard and every BLE peripheral.
          # Experimental exposes battery levels, as macOS shows for AirPods.
          Experimental = true;
          # Re-pairing a device that forgot this machine (AirPods after a
          # reset) is accepted instead of failing on the stale key.
          JustWorksRepairing = "always";
          FastConnectable = true;
        };
      };
    };

    services.blueman.enable = true;
  };
}

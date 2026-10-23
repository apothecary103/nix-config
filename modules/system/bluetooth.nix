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

  # blueman starts its tray applet through XDG autostart, which sway never
  # runs, so it comes up with the session instead.
  flake.modules.hjem.linux =
    { lib, pkgs, ... }:
    {
      systemd.services.blueman-applet = {
        description = "Bluetooth tray applet";
        wantedBy = [ "sway-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe' pkgs.blueman "blueman-applet";
          Restart = "on-failure";
        };
      };
    };
}

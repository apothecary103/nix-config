{
  flake.modules.nixos.base = {
    services.udisks2.enable = true;
    # Trash, network shares and MTP for the file manager.
    services.gvfs.enable = true;
  };

  # SD cards and USB drives mount on insertion and show up in the file
  # manager, as on macOS, with a notification for each.
  flake.modules.hjem.linux =
    { lib, pkgs, ... }:
    {
      systemd.services.udiskie = {
        description = "Automount removable media";
        wantedBy = [ "sway-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.udiskie} --automount --notify --no-tray";
          Restart = "on-failure";
        };
      };
    };
}

{
  # swayosd writes the backlight itself; its rules hand that to group video.
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      services.udev.packages = [ pkgs.swayosd ];
    };

  # The volume and brightness overlay macOS shows for the media keys. The sway
  # config binds the keys to swayosd-client.
  flake.modules.hjem.linux =
    { lib, pkgs, ... }:
    {
      packages = [ pkgs.swayosd ];

      systemd.services.swayosd = {
        description = "Volume and brightness overlay";
        wantedBy = [ "sway-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe' pkgs.swayosd "swayosd-server";
          Restart = "on-failure";
        };
      };
    };
}

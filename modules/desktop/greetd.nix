{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --time --remember --remember-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd niri-session";
            user = "greeter";
          };
        };
      };
    };
}

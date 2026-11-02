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
        # tuigreet owns its VT: boot messages and its own stderr stay off it.
        useTextGreeter = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --time --remember --remember-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd 'systemd-cat -t river river'";
            user = "greeter";
          };
        };
      };
    };
}

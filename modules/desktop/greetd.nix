{
  flake.modules.nixos.base =
    { pkgs, ... }:
    let
      # The tuigreet session menu (F3). Every Exec name resolves on the user's
      # login PATH: niri-session from programs.niri, Hyprland from the user's
      # own package set.
      sessions = pkgs.symlinkJoin {
        name = "greetd-wayland-sessions";
        paths = [
          (pkgs.writeTextDir "share/wayland-sessions/niri.desktop" ''
            [Desktop Entry]
            Name=Niri
            Comment=A scrollable-tiling Wayland compositor
            Exec=niri-session
            Type=Application
          '')
          (pkgs.writeTextDir "share/wayland-sessions/hyprland.desktop" ''
            [Desktop Entry]
            Name=Hyprland
            Comment=Dynamic tiling Wayland compositor
            Exec=Hyprland
            Type=Application
          '')
        ];
      };
    in
    {
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${sessions}/share/wayland-sessions --cmd niri-session";
          };
        };
      };
    };
}

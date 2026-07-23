{
  # niri reads this from locale1; hyprland sets its own kb_options separately.
  flake.modules.nixos.base.services.xserver.xkb.options = "compose:ralt";
}

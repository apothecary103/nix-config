{
  # niri leaves its own xkb block empty and reads this from locale1.
  flake.modules.nixos.base.services.xserver.xkb.options = "compose:ralt";
}

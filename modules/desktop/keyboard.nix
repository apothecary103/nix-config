{
  # For the console and greeter; sway.nix sets the same option for its session.
  flake.modules.nixos.base.services.xserver.xkb.options = "compose:ralt";
}

{
  # For the console and greeter (the console keymap follows the xkb settings);
  # kwim sets the same option for the river session.
  flake.modules.nixos.base = {
    services.xserver.xkb.options = "compose:ralt";
    console.useXkbConfig = true;
  };
}

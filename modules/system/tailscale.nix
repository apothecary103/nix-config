{
  flake.modules.nixos.base = {
    services.tailscale.enable = true;
  };

  flake.modules.darwin.base = {
    services.tailscale.enable = true;
  };
}

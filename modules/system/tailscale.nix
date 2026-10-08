let
  tailscale.services.tailscale.enable = true;
in
{
  flake.modules.nixos.base = tailscale;
  flake.modules.darwin.base = tailscale;
}

{
  flake.modules.nixos.base = {
    networking.wireless.iwd.enable = true;
    networking.useDHCP = true;
  };
}

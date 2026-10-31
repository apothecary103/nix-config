{
  # Mesa with Honeykrisp leaving input attachments uncompressed (see the
  # patch): river's 10-bit Vulkan scanout flickers otherwise. Only the runtime
  # driver package changes, so nothing that links Mesa is rebuilt.
  flake.modules.nixos."hosts/frieren" =
    { pkgs, ... }:
    {
      hardware.graphics.package = pkgs.mesa.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/mesa-hk-no-compressed-input-attachments.patch ];
      });
    };
}

{
  flake.modules.nixos."hosts/frieren" = {
    # macOS treats this Liquid Retina XDR panel as Display P3: its "Color LCD"
    # ColorSync profile is exactly P3 primaries, D65 white and the sRGB curve
    # with an identity vcgt, because DCP applies the factory calibration in
    # firmware. Untagged content is sRGB and gets mapped into P3. Under Linux
    # the same DCP does that mapping when a plane is tagged sRGB, which the
    # pinned kernel stopped doing for the internal panel.
    boot.kernelPatches = [
      {
        name = "appledrm-srgb-internal";
        patch = ./patches/appledrm-srgb-internal.patch;
      }
    ];
  };
}

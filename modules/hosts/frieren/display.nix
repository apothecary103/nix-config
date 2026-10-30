{
  flake.modules.nixos."hosts/frieren" = {
    # macOS treats this Liquid Retina XDR panel as Display P3: its "Color LCD"
    # ColorSync profile is exactly P3 primaries, D65 white and the sRGB curve
    # with an identity vcgt, because DCP applies the factory calibration in
    # firmware. Untagged content is sRGB and ColorSync maps it into P3 while
    # compositing. river does the same here (see river/patches/river): the
    # kernel leaves RGB planes NATIVE on the internal panel, so DCP passes the
    # P3 river composites straight through, and clients that tag wider content
    # through colour management keep it instead of having it clipped to sRGB.
    environment.sessionVariables.RIVER_DISPLAY_P3_OUTPUTS = "eDP-1";

    # XRGB2101010, river's 10-bit scanout, would read its X bits as alpha.
    boot.kernelPatches = [
      {
        name = "appledrm-xrgb2101010-premultiplied";
        patch = ./patches/appledrm-xrgb2101010-premultiplied.patch;
      }
    ];
  };
}

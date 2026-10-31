{
  # Palm rejection for this trackpad, from touches measured on it with evtest
  # (peak ABS_MT_TOUCH_MAJOR / MINOR): fingertips reach 394-834 / 732-836,
  # resting palms 2494-4110 / 978-1238 with grazes under 300, and the base of
  # the thumb 1324-1376 / 818-844. libinput's Apple quirk (1600, 150:130) lets
  # the thumb base and the grazes through. The pad reports pressure in grams
  # with a resolution, so libinput ignores it; size is all there is.
  #
  # 1200 takes the thumb base for a palm with room above the fingertips, so a
  # thumb resting on the pad neither moves the pointer nor counts as a finger
  # for clickfinger, as on macOS. 250:200 drops the grazes but keeps the
  # lightest fingertip. A size-based thumb rule can't help: libinput wants its
  # minor axis under 0.6 of the threshold, and this thumb is too round.
  flake.modules.nixos."hosts/frieren" = {
    environment.etc."libinput/local-overrides.quirks".text = ''
      [Apple MTP touchpad, measured]
      MatchUdevType=touchpad
      MatchName=Apple MTP multi-touch
      MatchVendor=0x05AC
      ModelAppleTouchpad=1
      AttrTouchSizeRange=250:200
      AttrPalmSizeThreshold=1200
    '';
  };
}

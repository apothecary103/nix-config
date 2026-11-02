{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  power = cfg.power;
in
{
  options.hardware.siliconBakery.power = {
    experimentalPmp = lib.mkEnableOption ''
      the Power Management Processor (patches/linux-pmp), which macOS always
      runs. The kernel's apple_pmp driver is built but idle until the device
      tree defines APPLE_USE_PMP; with it m1n1 hands the PMP its board
      tunables and the displays, the decoder and the camera report their
      power states to it. Asahi measured about 0.5 W less at idle on a 14"
      M1 Pro. Mac14,9 only, untested on the M2 Pro: a failure most likely
      shows as no display or no camera. Turning this on rebuilds the kernel'';
  };

  config = lib.mkIf (cfg.enable && power.experimentalPmp) {
    assertions = [
      {
        assertion = cfg.model == "Mac14,9";
        message = "hardware.siliconBakery.power.experimentalPmp: the device tree patch covers the Mac14,9 (j414s) only.";
      }
    ];

    boot.kernelPatches = lib.mkAfter pkgs.siliconBakery.kernelPatchesPmp;
  };
}

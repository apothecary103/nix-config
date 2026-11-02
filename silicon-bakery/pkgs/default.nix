# The patched packages, under pkgs.siliconBakery so that nothing else in
# nixpkgs is rebuilt against them: only what a module or a compositor picks
# up changes. Patches apply in file-name order after nixpkgs' own.
#
# What the overlay takes comes from a profile's measurements (the module
# passes them); without them it is upstream's behaviour plus the patches.
{
  # How long a three-finger drag outlives the fingers, in ms, if measured
  # (tools/mt-probe) to differ from the 625 ms patches/libinput/0005 takes
  # from macOS.
  threeFingerDragReleaseMs ? null,
}:
final: prev:
let
  inherit (final) lib;

  patchesIn =
    dir:
    map (name: dir + "/${name}") (lib.sort lib.lessThan (builtins.attrNames (builtins.readDir dir)));

  kernelPatchesIn =
    dir:
    map (patch: {
      name = lib.removeSuffix ".patch" (baseNameOf patch);
      inherit patch;
    }) (patchesIn dir);

  withPatches = dir: old: {
    patches = (old.patches or [ ]) ++ patchesIn dir;
  };
in
{
  siliconBakery = {
    # Palm rejection as macOS does it, by where a touch lands rather than
    # whether keys are held (0001), and no wobble hysteresis on Apple
    # trackpads (0002). Upstream's tests assert the old typing behaviour.
    # patches/libinput-1.32 is the same set refreshed for libinput 1.32
    # (its circular scrolling moved the context of 0001's last hunk).
    libinput = prev.libinput.overrideAttrs (
      old:
      withPatches (
        if lib.versionAtLeast old.version "1.32" then ../patches/libinput-1.32 else ../patches/libinput
      ) old
      // {
        doCheck = false;
      }
      // lib.optionalAttrs (threeFingerDragReleaseMs != null) {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/evdev-mt-touchpad-gestures.c \
            --replace-fail "#define DRAG_3FG_RELEASE_TIMEOUT usec_from_millis(625)" \
                           "#define DRAG_3FG_RELEASE_TIMEOUT usec_from_millis(${toString threeFingerDragReleaseMs})"
        '';
      }
    );

    # Backdrop blur for layer surfaces (0001), 8-bit formats offered to screen
    # capture from 10-bit outputs (0002), and HDR advertised for an EDID-less
    # internal panel whose driver takes it (0003; only with appledrm's
    # experimental_hdr does the kernel offer that).
    wlroots = (prev.wlroots_0_20.override { inherit (final.siliconBakery) libinput; }).overrideAttrs (
      withPatches ../patches/wlroots
    );

    # river with the panel's colour (Display P3 output transform, 10-bit
    # rendering), HDR on outputs that advertise it, and blur by namespace.
    river =
      (prev.river.override {
        wlroots_0_20 = final.siliconBakery.wlroots;
        inherit (final.siliconBakery) libinput;
      }).overrideAttrs
        (withPatches ../patches/river);

    # kwim with custom acceleration curves, for the macOS trackpad curves.
    kwim = final.callPackage ./kwim.nix { };

    # ffmpeg with the community AVE series for its V4L2 mem2mem encoders
    # (h264_v4l2m2m, hevc_v4l2m2m): stride and 1080-line handling, crop,
    # yuv420p input, -qp, B-frames, extradata for MP4/MKV. Its own package, so
    # nothing else rebuilds; stock ffmpeg covers basic NV12 encodes.
    ffmpeg-ave = prev.ffmpeg.overrideAttrs (withPatches ../patches/ffmpeg);

    # Honeykrisp leaving input attachments uncompressed: 10-bit Vulkan scanout
    # flickers the panel's edges otherwise (G14S). Meant for
    # hardware.graphics.package, so only the runtime driver changes.
    mesa = prev.mesa.overrideAttrs (withPatches ../patches/mesa);

    # For boot.kernelPatches, on top of nixos-apple-silicon's linux-asahi:
    # always (patches/linux), and for display.experimentalHdr and
    # display.experimentalVrr (patches/linux-hdr, patches/linux-vrr).
    kernelPatches = kernelPatchesIn ../patches/linux;
    kernelPatchesHdr = kernelPatchesIn ../patches/linux-hdr;
    kernelPatchesVrr = kernelPatchesIn ../patches/linux-vrr;
    # The AVE's device tree nodes (media.encode.deviceTree).
    kernelPatchesAve = kernelPatchesIn ../patches/linux-ave;
  };
}

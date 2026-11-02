# apple-scaler: Silicon Bakery's out-of-tree V4L2 mem2mem driver for the
# t6020 (M2 Pro) M2Scaler, plus its runtime device-tree overlay module
# (docs/scaler-port.txt has every value's provenance and the bring-up plan).
# Untested on hardware: written on the Mac14,9 under macOS.
#
#   config.boot.kernelPackages.callPackage ./apple-scaler.nix { }
#
# Installs lib/modules/<modDirVersion>/extra/apple-scaler.ko (module
# apple_scaler), extra/scaler-overlay.ko (module scaler_overlay) and
# bin/scaler-test. No firmware and no Apple data: filters and colour matrices
# are computed in the driver.
{
  lib,
  stdenv,
  kernel,
  # from the kernel package set's scope, as in apple-ave.nix
  kernelModuleMakeFlags ? kernel.commonMakeFlags ++ [
    "KBUILD_OUTPUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ],
  dtc,
  python3,
  makeWrapper,
  v4l-utils,
  gst_all_1,
  ffmpeg-headless,
  coreutils,
  gawk,
}:

stdenv.mkDerivation {
  pname = "apple-scaler";
  version = "0-unstable-2026-11-02";

  src = lib.fileset.toSource {
    root = ../drivers/apple-scaler;
    fileset = ../drivers/apple-scaler;
  };

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    dtc
    python3
    makeWrapper
  ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES ''${makeFlags[@]}
    make -C overlay -j$NIX_BUILD_CORES ''${makeFlags[@]}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 apple-scaler.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm644 overlay/scaler-overlay.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm755 ${../tools/scaler-test} $out/bin/scaler-test
    wrapProgram $out/bin/scaler-test --prefix PATH : ${
      lib.makeBinPath [
        v4l-utils
        gst_all_1.gstreamer
        ffmpeg-headless
        coreutils
        gawk
      ]
    } --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${
      lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" [
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
      ]
    }
    runHook postInstall
  '';

  meta = {
    description = "Apple M2Scaler (t6020) V4L2 mem2mem scaler/colour converter, out of tree";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    # untested on hardware; see docs/scaler-port.txt before loading it
  };
}

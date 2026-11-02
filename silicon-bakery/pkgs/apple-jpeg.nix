# apple-jpeg: the M2 Pro (t6020) hardware JPEG encoder/decoder as V4L2
# mem2mem devices, built out of tree against a kernel package set
# (docs/jpeg-port.txt has every value's provenance and the bring-up plan).
# Forked from aurora-silicon's T8140 encoder (GPL-2.0-only).
# Untested on hardware: written on the Mac14,9 under macOS.
#
#   config.boot.kernelPackages.callPackage ./apple-jpeg.nix { }
#
# Installs lib/modules/<modDirVersion>/extra/apple-jpeg.ko (module
# apple_jpeg) and extra/apple-jpeg-overlay.ko (module apple_jpeg_overlay,
# the runtime device tree overlay for kernels without patches/linux-jpeg).
# No firmware: quantisation tables are computed in the driver.
{
  lib,
  stdenv,
  kernel,
  # provided by the kernel package set's scope (pkgs/top-level/linux-kernels.nix):
  # kernel.commonMakeFlags (ARCH, CROSS_COMPILE, HOSTCC, Rust flags) + KBUILD_OUTPUT
  kernelModuleMakeFlags ? kernel.commonMakeFlags ++ [
    "KBUILD_OUTPUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ],
  dtc,
  python3,
}:

stdenv.mkDerivation {
  pname = "apple-jpeg";
  version = "0-unstable-2026-11-02-t6020";

  src = lib.fileset.toSource {
    root = ../drivers/apple-jpeg;
    fileset = ../drivers/apple-jpeg;
  };

  # The Makefile compiles the overlays with dtc and embeds them with python3.
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    dtc
    python3
  ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm644 apple-jpeg.ko apple-jpeg-overlay.ko \
      -t $out/lib/modules/${kernel.modDirVersion}/extra
    runHook postInstall
  '';

  meta = {
    description = "Apple M2 Pro (t6020) hardware JPEG encoder/decoder (V4L2 mem2mem), out of tree";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    # untested on hardware; see docs/jpeg-port.txt before loading it.
  };
}

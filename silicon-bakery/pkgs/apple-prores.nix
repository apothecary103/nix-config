# apple-prores: Silicon Bakery's V4L2 driver for the t6020 (M2 Pro) ProRes
# engine, built out of tree against a kernel package set
# (docs/prores-port.txt has every value's provenance and the bring-up plan).
# Untested on hardware: written on the Mac14,9 under macOS.
#
#   config.boot.kernelPackages.callPackage ./apple-prores.nix { }
#
# Installs lib/modules/<modDirVersion>/extra/apple-prores.ko (module
# apple_prores) and extra/prores-overlay.ko (module prores_overlay, the
# runtime device tree overlay for kernels without patches/linux-prores).
# The tunables file it requests (apple/prores-13.5-d0.bin) is made from
# Apple's macOS 13.5 by tools/bakery-prores-tables and is not here.
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags ? kernel.commonMakeFlags ++ [
    "KBUILD_OUTPUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ],
  dtc,
  python3,
}:

stdenv.mkDerivation {
  pname = "apple-prores";
  version = "0-unstable-2026-11-02";

  src = lib.fileset.toSource {
    root = ../drivers/apple-prores;
    fileset = ../drivers/apple-prores;
  };

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

  # Two Kbuild directories: the driver and the overlay loader.
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES ''${makeFlags[@]}
    make -C overlay -j$NIX_BUILD_CORES ''${makeFlags[@]}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 apple-prores.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm644 overlay/prores-overlay.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm644 apple-prores-uapi.h -t $out/include/apple-prores
    runHook postInstall
  '';

  meta = {
    description = "Apple ProRes engine (t6020) V4L2 mem2mem encoder/decoder, Silicon Bakery";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    # Untested on hardware; see docs/prores-port.txt before loading it.
  };
}

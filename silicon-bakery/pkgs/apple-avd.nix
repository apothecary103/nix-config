# apple-avd-bakery: Asahi's AVD (Apple Video Decoder) driver from the running
# kernel's own source, with Silicon Bakery's fixes (patches/linux-avd), built
# out of tree so it can replace the in-tree apple_avd without a kernel rebuild
# (docs/avd-port.txt has the evidence for each patch and the bring-up steps).
#
#   config.boot.kernelPackages.callPackage ./apple-avd.nix { }
#
# Installs lib/modules/<modDirVersion>/extra/apple-avd-bakery.ko (module
# apple_avd_bakery). It matches the same device tree compatibles and registers
# the same platform driver name ("avd") as the in-tree apple_avd, so the two
# cannot both bind: blacklist apple_avd (boot.blacklistedKernelModules), which
# keeps udev's modalias load from picking it, and udev loads this one instead.
# If both are loaded by hand, the second fails to register ("Driver 'avd' is
# already registered") and does nothing.
#
# The V4L2 side (v4l2-mem2mem, videobuf2-dma-contig, v4l2-h264, v4l2-vp9) comes
# from the kernel; it needs a kernel built with CONFIG_VIDEO_APPLE_AVD (which
# selects those), as linux-asahi is.
#
# patches/linux-avd/0003 (the V4L2 P210 pixel format) touches v4l2-core and
# the uAPI header, not the driver, so it is not applied here; it belongs in
# boot.kernelPatches. The driver uses P210 when the kernel's headers have it
# and otherwise refuses 4:2:2 10-bit streams.
{
  lib,
  stdenv,
  kernel,
  # provided by the kernel package set's scope (pkgs/top-level/linux-kernels.nix)
  kernelModuleMakeFlags ? kernel.commonMakeFlags ++ [
    "KBUILD_OUTPUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ],
}:

let
  patchDir = ../patches/linux-avd;
  # Only the patches against drivers/media/platform/apple/avd.
  driverPatches = map (n: patchDir + "/${n}") (
    lib.sort lib.lessThan (
      lib.filter (n: lib.hasSuffix ".patch" n && lib.hasInfix "media-apple-avd" n) (
        lib.attrNames (builtins.readDir patchDir)
      )
    )
  );
  avdDir = "drivers/media/platform/apple/avd";
in
stdenv.mkDerivation {
  pname = "apple-avd-bakery";
  version = "${kernel.modDirVersion}-bakery1";

  # The kernel's own source, so the driver always matches the running kernel.
  src = kernel.src;

  # Only the driver directory is needed; keep its place in the tree so the
  # patches apply with -p1.
  unpackPhase = ''
    runHook preUnpack
    mkdir -p source/${avdDir}
    if [ -d "$src" ]; then
      cp -r "$src/${avdDir}/." source/${avdDir}/
    else
      tar -xf "$src" --strip-components=1 -C source --wildcards '*/${avdDir}/*'
    fi
    chmod -R u+w source
    sourceRoot=source
    runHook postUnpack
  '';

  patches = driverPatches;

  # Kbuild takes precedence over the in-tree Makefile. A different object
  # name keeps the module from colliding with the in-tree apple-avd.ko.
  postPatch = ''
    cat > ${avdDir}/Kbuild <<'EOF'
    obj-m += apple-avd-bakery.o
    apple-avd-bakery-y := avd-drv.o avd-v4l2.o avd-hw.o avd-h264.o avd-vp9.o \
    	avd-hevc.o avd-av1.o avd-av1-entropymode.o
    EOF
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  hardeningDisable = [
    "pic"
    "format"
  ];

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  buildPhase = ''
    runHook preBuild
    make ''${makeFlags[@]} M=$PWD/${avdDir} -j$NIX_BUILD_CORES modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 ${avdDir}/apple-avd-bakery.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    runHook postInstall
  '';

  meta = {
    description = "Asahi AVD video decoder (V4L2 stateless) with Silicon Bakery's fixes, as an out-of-tree module";
    homepage = "https://github.com/AsahiLinux/linux";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}

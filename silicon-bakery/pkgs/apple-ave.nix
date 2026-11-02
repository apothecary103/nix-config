# apple-ave: the community AVE (Apple Video Encoder) V4L2 driver with Silicon
# Bakery's t6020 (M2 Pro) port, built out of tree against a kernel package set
# (docs/ave-port.txt has every value's provenance and the bring-up plan).
# Untested on hardware: written on the Mac14,9 under macOS.
#
#   config.boot.kernelPackages.callPackage ./apple-ave.nix { }
#
# Installs lib/modules/<modDirVersion>/extra/apple-ave.ko (module apple_ave),
# extra/ave-overlay.ko (module ave_overlay, the runtime device tree overlay,
# variant=15 on t6020) and share/apple-ave/. The firmware it requests is
# Apple's and is not here: tools/bakery-ave-fw makes it from the owner's own
# macOS 13.5, for media.encode.firmware.
{
  lib,
  stdenv,
  fetchFromGitHub,
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
  pname = "apple-ave";
  version = "0-unstable-2026-10-18-t6020";

  src = fetchFromGitHub {
    owner = "aquarat";
    repo = "apple-m-series-ave-driver";
    rev = "9ab14e45281e8f61fb499b760408028171a5f2b5";
    # nix hash path over `git archive` of the rev and over GitHub's own
    # tarball of it: both sha256-Q3Bkd5O9...
    hash = "sha256-Q3Bkd5O9pEiqEBF++8isagevBqy4Fj2m5Qb5VD2k0xw=";
  };

  # The t6020 port (SoC row, AXI2AF tunables, ADT DVAs, overlay variant=15).
  patches = [ ../patches/apple-ave/0001-t6020.patch ];

  # test/Makefile compiles the overlays with dtc and embeds them with python3.
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    dtc
    python3
  ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  makeFlags = kernelModuleMakeFlags ++ [
    # driver/Makefile and test/Makefile both take KDIR (default: the running kernel's)
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  # Two Kbuild directories, no top-level Makefile. test/ also builds the
  # physdump and isp_peek research modules; they are not installed.
  buildPhase = ''
    runHook preBuild
    make -C driver -j$NIX_BUILD_CORES ''${makeFlags[@]}
    make -C test -j$NIX_BUILD_CORES ''${makeFlags[@]}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 driver/apple-ave.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm644 test/ave-overlay.ko -t $out/lib/modules/${kernel.modDirVersion}/extra
    install -Dm755 tools/v4l2-test.sh -t $out/share/apple-ave
    install -Dm644 tools/ave_fwgen.py -t $out/share/apple-ave
    runHook postInstall
  '';

  meta = {
    description = "Apple AVE hardware H.264/HEVC encoder (V4L2 mem2mem), community driver with the t6020 port";
    homepage = "https://github.com/aquarat/apple-m-series-ave-driver";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    # t6020 support is untested on hardware; see PORT.txt before loading it.
  };
}

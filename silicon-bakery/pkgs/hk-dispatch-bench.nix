# hk-dispatch-bench: compute dispatch cost on the Vulkan driver, and whether
# dispatches stay ordered across pipeline barriers (../tools/hk-dispatch-bench).
{
  lib,
  stdenv,
  glslang,
  vulkan-headers,
  vulkan-loader,
}:
stdenv.mkDerivation {
  pname = "hk-dispatch-bench";
  version = "1";

  src = ../tools/hk-dispatch-bench;

  nativeBuildInputs = [ glslang ];
  buildInputs = [
    vulkan-headers
    vulkan-loader
  ];

  buildPhase = ''
    runHook preBuild
    glslangValidator -V --vn bench_spv -o bench.spv.h bench.comp
    $CC -O2 -Wall -Werror main.c -lvulkan -o hk-dispatch-bench
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 hk-dispatch-bench $out/bin/hk-dispatch-bench
    runHook postInstall
  '';

  meta = {
    description = "Vulkan compute dispatch cost and ordering checks";
    mainProgram = "hk-dispatch-bench";
    platforms = lib.platforms.unix;
  };
}

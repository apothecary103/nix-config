# bakery-truetoned: True Tone on the built-in panel, CoreBrightness's colour
# engine transliterated to C (../tools/truetone, docs/truetone.md). It reads
# the AOP's ambient light sensor and sets the panel's DCP matrix through
# appledrm's ambient_matrix, both from patches/linux-truetone.
#
# No Apple data: the tables come at run time from apple/truetone.bin, which
# tools/bakery-truetone-tables writes from the owner's macOS.
{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "bakery-truetoned";
  version = "1";

  src = lib.fileset.toSource {
    root = ../tools/truetone;
    fileset = lib.fileset.unions (
      map (f: ../tools/truetone + "/${f}") [
        "cfx.c"
        "cfx.h"
        "tables.c"
        "tables.h"
        "truetoned.c"
      ]
    );
  };

  # The engine follows CoreBrightness's arm64 code to the bit: its fused
  # multiply-adds are written out, so the compiler must not add more.
  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -O2 -Wall -Wextra -Werror -ffp-contract=off \
      truetoned.c cfx.c tables.c -lm -o bakery-truetoned
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bakery-truetoned $out/bin/bakery-truetoned
    runHook postInstall
  '';

  meta = {
    description = "True Tone for Apple Silicon panels, as macOS's CoreBrightness does it";
    mainProgram = "bakery-truetoned";
    platforms = lib.platforms.linux;
  };
}

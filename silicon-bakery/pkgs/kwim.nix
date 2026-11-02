# kwim, the input configurator kwm starts, with custom acceleration curves
# (../patches/kwim/0001-accel-custom.patch) for the macOS trackpad curves.
{
  lib,
  stdenv,
  fetchFromGitHub,
  libxkbcommon,
  pkg-config,
  wayland,
  wayland-protocols,
  wayland-scanner,
  zig_0_16,
}:
let
  zig = zig_0_16;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kwim";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "kewuaa";
    repo = "kwim";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ewg259zRCMGq75XXMmPqoFwD5NBEFXXsIj1rvMy31uw=";
  };

  patches = [ ../patches/kwim/0001-accel-custom.patch ];

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-rOZZu/Y/rZ7who3hl1qIBHXZtRP7s4FXo0+LNnM6dYo=";
  };

  postConfigure = ''
    ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    zig
  ];

  buildInputs = [
    libxkbcommon
    wayland
    wayland-protocols
    wayland-scanner
  ];

  zigBuildFlags = [ "-Dversion-string=${finalAttrs.version}" ];

  meta = {
    description = "Input configurator for river";
    homepage = "https://github.com/kewuaa/kwim";
    license = lib.licenses.gpl3Only;
    mainProgram = "kwim";
    platforms = lib.platforms.linux;
  };
})

# kwm, a dwm-like window manager for river's window management protocol, with
# a bar height option (./patches/kwm/0001-bar-height.patch) so the bar clears the
# notch. It starts kwim itself.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fcft,
  kwim,
  libxkbcommon,
  makeWrapper,
  pixman,
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
  pname = "kwm";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "kewuaa";
    repo = "kwm";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hX76wTHPTgg5RAHILfd3CjRKPlgAwGSK3lG82IFoUUs=";
  };

  patches = [ ./patches/kwm/0001-bar-height.patch ];

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    fetchAll = true;
    hash = "sha256-Lz/Wcy40rxN81n/mBj4YJVbyGOolHzSFZMs93T1h0oQ=";
  };

  postConfigure = ''
    ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  strictDeps = true;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    wayland-scanner
    zig
  ];

  buildInputs = [
    fcft
    libxkbcommon
    pixman
    wayland
    wayland-protocols
    wayland-scanner
  ];

  zigBuildFlags = [ "-Dversion-string=${finalAttrs.version}" ];

  postInstall = ''
    wrapProgram $out/bin/kwm --prefix PATH : ${lib.makeBinPath [ kwim ]}
  '';

  meta = {
    description = "dwm-like window manager for river";
    homepage = "https://github.com/kewuaa/kwm";
    license = lib.licenses.gpl3Only;
    mainProgram = "kwm";
    platforms = lib.platforms.linux;
  };
})

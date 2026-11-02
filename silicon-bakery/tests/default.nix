# Flake checks, runnable on Linux and on macOS alike:
#
# - accel: the trackpad curves against IOHIDFamily's arithmetic, for every
#   profile with a reference (tests/accel.nix);
# - patches-*: every patch set applies, in order and without fuzz, to the
#   exact sources an aarch64-linux system builds (nixpkgs' own patches first),
#   fetched again here so a Mac can check them without a Linux builder.
{
  # Packages for the machine running the checks.
  pkgs,
  # aarch64-linux packages with nixos-apple-silicon's and Silicon Bakery's
  # overlays, only evaluated for their sources and patch lists.
  target,
}:
let
  inherit (pkgs) lib;
  accel = import ./accel.nix { inherit lib; };

  # The same source, fetched by this machine: the hash pins the contents.
  fetchHere =
    src:
    if lib.hasSuffix ".git" src.url then
      pkgs.fetchgit {
        inherit (src) url rev;
        fetchSubmodules = src.fetchSubmodules or false;
        hash = src.outputHash;
      }
    else
      pkgs.fetchzip {
        inherit (src) name url;
        hash = src.outputHash;
      };

  patchesIn =
    dir:
    map (name: dir + "/${name}") (lib.sort lib.lessThan (builtins.attrNames (builtins.readDir dir)));

  apple-ave = target.linux-asahi.callPackage ../pkgs/apple-ave.nix { };

  # nixpkgs' own patches go on first, as stdenv applies them (fuzz allowed);
  # Silicon Bakery's must then apply without fuzz.
  applies =
    name: src: upstream: ours:
    pkgs.runCommand "silicon-bakery-patches-${name}"
      {
        src = fetchHere src;
        inherit upstream ours;
        nativeBuildInputs = [ pkgs.patch ];
      }
      ''
        cp -r --no-preserve=mode "$src" source
        cd source
        for p in $upstream; do
          echo "applying nixpkgs' $(stripHash "$p")"
          patch -p1 -f --no-backup-if-mismatch < "$p"
        done
        for p in $ours; do
          echo "applying $(stripHash "$p")"
          patch -p1 -f --no-backup-if-mismatch < "$p" | tee ../log
          if grep -q 'with fuzz' ../log; then
            echo "$(stripHash "$p") only applies with fuzz; refresh it" >&2
            exit 1
          fi
        done
        touch "$out"
      '';

  # A package's patches split into nixpkgs' and ours (those under ../patches).
  split =
    pkg:
    let
      mine = p: lib.hasPrefix (toString ../patches) (toString p);
    in
    {
      upstream = builtins.filter (p: !mine p) pkg.patches;
      ours = builtins.filter mine pkg.patches;
    };
  appliesTo =
    name: src: pkg:
    let
      parts = split pkg;
    in
    applies name src parts.upstream parts.ours;
in
{
  accel = pkgs.runCommand "silicon-bakery-accel" { } (
    if accel.failures == [ ] then
      ''
        echo "${toString accel.checked} profile(s) follow IOHIDFamily's curves"
        touch "$out"
      ''
    else
      ''
        echo ${lib.escapeShellArg (lib.concatStringsSep "\n" accel.failures)} >&2
        exit 1
      ''
  );

  # The always-on kernel patches with every opt-in set on top.
  patches-linux = applies "linux" target.linux-asahi.kernel.src [ ] (
    map (p: p.patch) (
      target.siliconBakery.kernelPatches
      ++ target.siliconBakery.kernelPatchesHdr
      ++ target.siliconBakery.kernelPatchesVrr
      ++ target.siliconBakery.kernelPatchesAve
    )
  );
  patches-mesa = appliesTo "mesa" target.mesa.src target.siliconBakery.mesa;
  patches-libinput = appliesTo "libinput" target.libinput.src target.siliconBakery.libinput;
  patches-wlroots = appliesTo "wlroots" target.wlroots_0_20.src target.siliconBakery.wlroots;
  patches-river = appliesTo "river" target.river.src target.siliconBakery.river;
  patches-kwim = appliesTo "kwim" target.siliconBakery.kwim.src target.siliconBakery.kwim;
  patches-apple-ave = appliesTo "apple-ave" apple-ave.src apple-ave;
  patches-ffmpeg = appliesTo "ffmpeg" target.ffmpeg.src target.siliconBakery.ffmpeg-ave;

  # The libinput set for 1.32, ahead of nixpkgs moving to it.
  patches-libinput-1_32 = applies "libinput-1.32" {
    name = "source";
    url = "https://gitlab.freedesktop.org/api/v4/projects/libinput%2Flibinput/repository/archive.tar.gz?sha=1.32.0";
    outputHash = "sha256-nPvnFqb/t+1IKbdDzmr5ht/BG2OAl1AJm1c24lBULoM=";
  } [ ] (patchesIn ../patches/libinput-1.32);
}

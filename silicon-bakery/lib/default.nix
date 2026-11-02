{ lib }:
let
  profiles = ../profiles;
in
rec {
  # macOS trackpad acceleration as libinput custom curves; see macos-accel.nix.
  macosAccel = import ./macos-accel.nix { inherit lib; };

  # Models with a profile.
  models = builtins.attrNames (builtins.readDir profiles);

  # A model's profile: what tools/bakery-probe read from macOS
  # (profiles/<model>/macos.json), with what was measured on Linux
  # (profiles/<model>/linux.json) laid over it.
  profile =
    model:
    let
      dir = profiles + "/${model}";
      linux = dir + "/linux.json";
    in
    if !builtins.pathExists (dir + "/macos.json") then
      throw ''
        silicon-bakery: no profile for ${model}. On that Mac, under macOS, run
          tools/bakery-probe > profiles/${model}/macos.json
        from the silicon-bakery checkout.''
    else
      lib.recursiveUpdate (lib.importJSON (dir + "/macos.json")) (
        lib.optionalAttrs (builtins.pathExists linux) (lib.importJSON linux)
      );
}

# nix build .#zmk        → both halves' .uf2 in ./result
# nix run   .#zmk-flash   → copy firmware to a mounted controller
# nix run   .#zmk-update  → bump West deps and the zephyrDepsHash below
{
  lib,
  zmk-nix,
  system,
}: rec {
  default = zmk;

  zmk = zmk-nix.legacyPackages.${system}.buildSplitKeyboard {
    name = "zmk-cradio";
    src = lib.sourceFilesBySuffices ./. [".conf" ".keymap" ".yml"];
    board = "nice_nano_v2";
    shield = "cradio_%PART%";
    zephyrDepsHash = "sha256-gsqiTDJLAihVyBXVFlgXwqRmlREcFJctKpl4tEWmVlY=";
    meta = {
      description = "ZMK firmware for the cradio split (nice_nano_v2)";
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
    };
  };

  zmk-flash = zmk-nix.packages.${system}.flash.override {firmware = zmk;};
  zmk-update = zmk-nix.packages.${system}.update;
}

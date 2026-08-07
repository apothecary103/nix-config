{ inputs, ... }: {
  perSystem =
    {
      lib,
      system,
      ...
    }:
    {
      packages =
        let
          zmk = inputs.zmk-nix.legacyPackages.${system}.buildSplitKeyboard {
            name = "zmk-cradio";
            src = lib.sourceFilesBySuffices ../../zmk [
              ".conf"
              ".keymap"
              ".yml"
            ];
            board = "nice_nano_v2";
            shield = "cradio_%PART%";
            zephyrDepsHash = "sha256-gsqiTDJLAihVyBXVFlgXwqRmlREcFJctKpl4tEWmVlY=";
            meta = {
              description = "ZMK firmware for the cradio split (nice_nano_v2)";
              license = lib.licenses.mit;
              platforms = lib.platforms.all;
            };
          };
        in
        {
          default = zmk;
          inherit zmk;
          zmk-flash = inputs.zmk-nix.packages.${system}.flash.override { firmware = zmk; };
          zmk-update = inputs.zmk-nix.packages.${system}.update;
        };

      devShells.zmk = inputs.zmk-nix.devShells.${system}.default;
    };
}

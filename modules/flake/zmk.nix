{ inputs, ... }: {
  perSystem =
    {
      lib,
      pkgs,
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
          zmk-update = inputs.zmk-nix.packages.${system}.update;
        }
        // {
          zmk-flash =
            if pkgs.stdenv.hostPlatform.isDarwin then
              pkgs.writeShellApplication {
                name = "zmk-uf2-flash";
                text = ''
                  mounted() {
                    /usr/bin/find /Volumes -mindepth 2 -maxdepth 2 -name INFO_UF2.TXT -print -quit 2>/dev/null \
                      | /usr/bin/sed 's|/INFO_UF2.TXT$||'
                  }

                  parts=(${lib.escapeShellArgs zmk.parts})
                  flash=("$@")

                  if [ "''${#flash[@]}" -eq 0 ]; then
                    flash=("''${parts[@]}")
                  else
                    for part in "''${flash[@]}"; do
                      valid=false
                      for candidate in "''${parts[@]}"; do
                        [ "$candidate" = "$part" ] && valid=true
                      done
                      if [ "$valid" != true ]; then
                        echo "The '$part' part does not exist in ${zmk.name}" >&2
                        exit 1
                      fi
                    done
                  fi

                  for part in "''${flash[@]}"; do
                    while [ -n "$(mounted)" ]; do
                      echo "Unmount the existing UF2 volume before flashing the '$part' half." >&2
                      /bin/sleep 2
                    done

                    echo "Double-tap reset on the '$part' half, then connect it over USB."
                    mountpoint=""
                    while [ -z "$mountpoint" ]; do
                      mountpoint="$(mounted)"
                      [ -n "$mountpoint" ] || /bin/sleep 1
                    done

                    firmware_file="${zmk}/zmk_$part.uf2"
                    echo "Copying $(/usr/bin/basename "$firmware_file") to $mountpoint"
                    if ! /bin/cp -X "$firmware_file" "$mountpoint/"; then
                      # UF2 controllers reboot and disappear as soon as the copy is
                      # complete, which macOS can report as a write error.
                      [ ! -d "$mountpoint" ] || exit 1
                    fi

                    while [ -d "$mountpoint" ]; do
                      /bin/sleep 1
                    done
                    echo "Flashed the '$part' half."
                  done
                '';

                meta = zmk.meta // {
                  description = "Flash ZMK UF2 firmware from macOS";
                  mainProgram = "zmk-uf2-flash";
                  platforms = lib.platforms.darwin;
                };
              }
            else
              inputs.zmk-nix.packages.${system}.flash.override { firmware = zmk; };
        };

      devShells.zmk = inputs.zmk-nix.devShells.${system}.default;
    };
}

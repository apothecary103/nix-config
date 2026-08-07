{
  lib,
  stdenvNoCC,
  fetchurl,
  bash,
  rsync,
  coreutils,
  writeText,
}:
let
  # Bump this and the per-variant `hash` fields together. The launchers' own
  # self-updater still pulls point releases between Nix upgrades.
  version = "0.3.18";

  # yaagl's `Contents/MacOS/parameterized` launcher rsyncs the bundle's
  # `Resources/` into a writable `~/Library/Application Support/<distName>/` and
  # runs Neutralino from there, which is why the self-updater works at all.
  # Replaced below with an equivalent that uses Nix's rsync/coreutils (recent
  # macOS dropped the system rsync) and drives the sync by version stamp, so a
  # Nix upgrade lands cleanly without clobbering a newer in-app update.
  mkYaagl =
    {
      pname,
      distName,
      asset,
      hash,
      description,
    }:
    let
      appBundle = "${distName}.app";

      parameterized = writeText "yaagl-${pname}-parameterized" ''
        #!${bash}/bin/bash
        set -euo pipefail
        export PATH="${coreutils}/bin:${rsync}/bin:$PATH"

        SCRIPT_DIR="$(cd -- "$(dirname -- "''${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
        CONTENTS_DIR="$(dirname "$SCRIPT_DIR")"
        APST_DIR="''${HOME}/Library/Application Support/${distName}"
        STAMP="$APST_DIR/.nix-installed-version"
        NIX_VER="${version}"

        mkdir -p "$APST_DIR"

        # Decide how to sync the immutable store resources -> Application Support.
        #   full  : nix version is newer than what we last stamped  -> overwrite
        #   update: same nix version (maybe user self-updated)      -> keep newer
        #   skip  : user is ahead of nix (or nix rolled back)       -> touch nothing
        CURRENT=""
        [ -f "$STAMP" ] && CURRENT="$(cat "$STAMP" 2>/dev/null || true)"

        sync_mode="update"
        if [ -z "$CURRENT" ]; then
          sync_mode="full"
        elif [ "$CURRENT" = "$NIX_VER" ]; then
          sync_mode="update"
        elif printf '%s\n%s\n' "$CURRENT" "$NIX_VER" | sort -V -C 2>/dev/null; then
          sync_mode="full"
        else
          sync_mode="skip"
        fi

        case "$sync_mode" in
          full)
            # No --delete: never wipe user settings (.storage) or game data.
            rsync -rlpt "$CONTENTS_DIR/Resources/." "$APST_DIR/"
            printf '%s' "$NIX_VER" > "$STAMP"
            ;;
          update)
            # -u keeps files in the destination that are newer, so an in-app
            # self-update applied to Application Support is preserved.
            rsync -rlptu "$CONTENTS_DIR/Resources/." "$APST_DIR/"
            ;;
          skip)
            :
            ;;
        esac

        cd "$APST_DIR"
        exec "$SCRIPT_DIR/Yaagl" --path="$APST_DIR"
      '';
    in
    stdenvNoCC.mkDerivation {
      pname = "yaagl-${pname}";
      inherit version;

      src = fetchurl {
        name = asset;
        url = "https://github.com/yaagl/yet-another-anime-game-launcher/releases/download/${version}/${asset}";
        inherit hash;
      };

      dontConfigure = true;
      dontBuild = true;
      dontStrip = true;
      dontPatchELF = true;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/Applications"
        tar -xzf "$src" -C "$out/Applications" --no-same-owner

        app="$out/Applications/${appBundle}"
        chmod +x "$app/Contents/MacOS/Yaagl"

        cp ${parameterized} "$app/Contents/MacOS/parameterized"
        chmod +x "$app/Contents/MacOS/parameterized"

        mkdir -p "$out/bin"
        cat > "$out/bin/yaagl-${pname}" <<BIN
        #!${bash}/bin/bash
        exec "$out/Applications/${appBundle}/Contents/MacOS/parameterized"
        BIN
        chmod +x "$out/bin/yaagl-${pname}"

        runHook postInstall
      '';

      meta = {
        inherit description;
        homepage = "https://github.com/yaagl/yet-another-anime-game-launcher";
        license = lib.licenses.mit;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        platforms = lib.platforms.darwin;
        mainProgram = "yaagl-${pname}";
      };
    };

  # One entry per game / region. `distName` is both the .app bundle name and the
  # `~/Library/Application Support/<distName>` folder yaagl runs from.
  variants = [
    {
      pname = "genshin-cn";
      distName = "Yaagl";
      asset = "Yaagl.app.tar.gz";
      hash = "sha256-W22NlsRFv9H5Bd9XwAYRUyZRFwMrHy7xn6y6sK0JTDA=";
      description = "Yet Another Anime Game Launcher — Genshin Impact (CN / miHoYo)";
    }
    {
      pname = "genshin-os";
      distName = "Yaagl OS";
      asset = "Yaagl.OS.app.tar.gz";
      hash = "sha256-CWrsaF3dAAH5Gx1iKFgbkFTAFZjDnQF/C43ovsHEa+c=";
      description = "Yet Another Anime Game Launcher — Genshin Impact (Global / HoYoverse)";
    }
    {
      pname = "hsr-cn";
      distName = "Yaagl HSR";
      asset = "Yaagl.HSR.app.tar.gz";
      hash = "sha256-pM6BwMm+md3lsaEakn1qlFim3HZ17bZ0nnaPOMe80jU=";
      description = "Yet Another Anime Game Launcher — Honkai: Star Rail (CN / miHoYo)";
    }
    {
      pname = "hsr-os";
      distName = "Yaagl HSR OS";
      asset = "Yaagl.HSR.OS.app.tar.gz";
      hash = "sha256-TZQcsN4sZgFPlHeXEwQyVmHGByEfn44xONKhRQ2oaQU=";
      description = "Yet Another Anime Game Launcher — Honkai: Star Rail (Global / HoYoverse)";
    }
    {
      pname = "zzz-cn";
      distName = "Yaagl ZZZ";
      asset = "Yaagl.ZZZ.app.tar.gz";
      hash = "sha256-jl9jVWSmOSDfUVHjrw5LJ8F7kMAxWa3Iq0x5SUuQBDU=";
      description = "Yet Another Anime Game Launcher — Zenless Zone Zero (CN / miHoYo)";
    }
    {
      pname = "zzz-os";
      distName = "Yaagl ZZZ OS";
      asset = "Yaagl.ZZZ.OS.app.tar.gz";
      hash = "sha256-GS863FRxW97wuV6IHqc6C6AGNuGycE0A80o4AIa7Jhc=";
      description = "Yet Another Anime Game Launcher — Zenless Zone Zero (Global / HoYoverse)";
    }
  ];
in
builtins.listToAttrs (
  map (v: {
    name = "yaagl-${v.pname}";
    value = mkYaagl v;
  }) variants
)

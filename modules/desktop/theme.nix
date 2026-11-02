{ inputs, ... }:
let
  flavour = "macchiato";

  # Catppuccin's fourteen accents.
  accents = [
    "rosewater"
    "flamingo"
    "pink"
    "mauve"
    "red"
    "maroon"
    "peach"
    "yellow"
    "green"
    "teal"
    "sky"
    "sapphire"
    "blue"
    "lavender"
  ];
in
{
  flake.modules.hjem.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      palette = inputs.orchard.palettes.catppuccin.${flavour}.native;

      matugenConfig = pkgs.writeText "matugen.toml" ''
        [config]

        [templates]
      '';
      candidates = pkgs.writeText "accents" (
        lib.concatMapStrings (name: "${name} ${palette.${name}}\n") accents
      );
      # matugen's source colour for an image, then the Catppuccin accent
      # nearest it in hue (accent.py).
      pick = image: ''
        source=$(matugen image ${image} --config ${matugenConfig} --type scheme-tonal-spot --prefer saturation \
          --include-image-in-json false --json hex --dry-run | jq -r '.colors.source_color.dark.color')
        python3 -I ${./accent.py} "$source" ${candidates}
      '';

      # The accent the wallpaper river starts with (see river/config.nix)
      # suggests, for everything themed when the system is built.
      wallpaperAccent =
        image:
        builtins.readFile (
          pkgs.runCommand "wallpaper-accent" {
            nativeBuildInputs = [
              pkgs.matugen
              pkgs.jq
              pkgs.python3
            ];
          } "{ ${pick image}} > $out"
        );
      fallback = wallpaperAccent ../../assets/botanical-shop.png;

      live = config.accent.live;
      state = "${config.directory}/.local/state/accent";

      # The accent of whatever awww shows, written into every template in
      # accent.live: once (before the programs that read them start), or on
      # every change of wallpaper, telling each program to reload.
      accent = pkgs.writeShellApplication {
        name = "accent";
        runtimeInputs = [
          pkgs.awww
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnused
          pkgs.jq
          pkgs.matugen
          pkgs.python3
        ];
        text = ''
          state=${state}
          mkdir -p "$state/cache"

          # Nothing (rather than the script's end, under pipefail) while the
          # wallpaper daemon is not answering.
          image() { awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1 || true; }

          # The accent for an image, remembered by path and modification time.
          name_for() {
            local key
            key=$(printf '%s %s' "$1" "$(stat -c %Y "$1" 2>/dev/null)" | sha256sum | cut -c1-32)
            if [ ! -s "$state/cache/$key" ]; then
              local tmp
              tmp=$(mktemp "$state/cache/$key.XXXXXX")
              { ${pick ''"$1"''}} > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
              mv -f "$tmp" "$state/cache/$key"
            fi
            cat "$state/cache/$key"
          }

          # eww, mako and the watcher render at the same moment when the
          # session starts, so each writes through a file of its own.
          render() {
            local hex tmp
            hex=$(awk -v n="$1" '$1 == n { print substr($2, 2) }' ${candidates})
            [ -n "$hex" ] || return 1
            ${lib.concatMapStrings (file: ''
              mkdir -p "$(dirname ${lib.escapeShellArg file.path})"
              tmp=$(mktemp ${lib.escapeShellArg file.path}.XXXXXX)
              sed "s/@accent@/$hex/g" ${pkgs.writeText "accent-template" file.template} > "$tmp"
              mv -f "$tmp" ${lib.escapeShellArg file.path}
            '') (lib.attrValues live)}
            printf '%s\n' "$1" > "$state/name"
          }

          reload() {
            ${lib.concatMapStrings (file: lib.optionalString (file.reload != null) ''
              timeout 5 ${pkgs.writeShellScript "accent-reload" file.reload} >/dev/null 2>&1 || true
            '') (lib.attrValues live)}
          }

          current=$(cat "$state/name" 2>/dev/null || echo ${fallback})
          case "''${1:-watch}" in
            once)
              picture=$(image)
              if [ -n "$picture" ]; then current=$(name_for "$picture" || echo "$current"); fi
              render "$current"
              ;;
            watch)
              shown=""
              while :; do
                picture=$(image)
                if [ -n "$picture" ] && [ "$picture" != "$shown" ]; then
                  shown=$picture
                  if name=$(name_for "$picture") && [ "$name" != "$current" ]; then
                    current=$name
                    render "$current" && reload
                  fi
                fi
                sleep 2
              done
              ;;
          esac
        '';
      };
    in
    {
      imports = [ inputs.orchard.hjemModules.default ];

      # Files that follow the wallpaper's accent while the session runs: each
      # template with @accent@ for its hex (no #), written to path, and reload
      # run after a change. The programs' own configs keep the accent the
      # system was built with, for before the first wallpaper.
      options.accent.live = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              template = lib.mkOption { type = lib.types.lines; };
              path = lib.mkOption { type = lib.types.str; };
              reload = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = { };
      };

      config = {
        # Catppuccin Macchiato for every program orchard themes and the shell,
        # in the accent the wallpaper suggests: the build's picks from the
        # wallpaper river starts with, the session's from whatever awww shows.
        orchard = {
          enable = true;
          theme = "catppuccin";
          inherit flavour;
          accent = fallback;
        };

        # Shorter names for the hand-styled configs orchard covers no port for,
        # and the live accent's renderer and state for the files that use it.
        _module.args.palette = config.orchard.palette;
        _module.args.theme = config.orchard;
        _module.args.accent = {
          bin = lib.getExe accent;
          render = "${lib.getExe accent} once";
          inherit state;
        };
      };
    };

  flake.modules.hjem.linux =
    { accent, ... }:
    {
      # Every two seconds awww is asked what it shows: cheap, and awww says
      # nothing on its own when the wallpaper changes.
      systemd.services.accent = {
        description = "Accent from the wallpaper";
        wantedBy = [ "river-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStartPre = accent.render;
          ExecStart = "${accent.bin} watch";
          Restart = "on-failure";
        };
      };
    };
}

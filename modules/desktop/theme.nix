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

      # The accent the wallpaper river shows (see river/config.nix) suggests:
      # matugen's source colour, matched by hue alone to the nearest of
      # Catppuccin's accents, so the picture picks the colour and Catppuccin
      # keeps its own.
      wallpaperAccent =
        image:
        let
          config = pkgs.writeText "matugen.toml" ''
            [config]

            [templates]
          '';
          candidates = pkgs.writeText "accents" (
            lib.concatMapStrings (name: "${name} ${palette.${name}}\n") accents
          );
        in
        builtins.readFile (
          pkgs.runCommand "wallpaper-accent" { nativeBuildInputs = [ pkgs.matugen pkgs.jq ]; } ''
            source=$(matugen image ${image} --config ${config} --type scheme-tonal-spot --prefer saturation \
              --include-image-in-json false --json hex --dry-run | jq -r '.colors.source_color.dark.color')
            ${pkgs.python3}/bin/python3 -I - "$source" ${candidates} > $out <<'PY'
            import math, sys

            def hue(hex):
                r, g, b = (int(hex.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
                r, g, b = (c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))
                l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
                m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
                s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
                a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
                b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
                return math.atan2(b, a)

            def distance(x, y):
                d = abs(x - y) % (2 * math.pi)
                return min(d, 2 * math.pi - d)

            source = hue(sys.argv[1])
            names = [line.split() for line in open(sys.argv[2]) if line.strip()]
            print(min(names, key=lambda n: distance(hue(n[1]), source))[0], end="")
            PY
          ''
        );
    in
    {
      imports = [ inputs.orchard.hjemModules.default ];

      # Catppuccin Macchiato for every program orchard themes and the shell,
      # in the accent the wallpaper suggests.
      orchard = {
        enable = true;
        theme = "catppuccin";
        inherit flavour;
        accent = wallpaperAccent ../../assets/botanical-shop.png;
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

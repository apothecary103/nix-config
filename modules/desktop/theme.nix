{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      orchard = {
        enable = true;
        # Under sway the wallpaper sets the colours (see sway/config.nix); this
        # is what everything starts from and what programs it misses keep.
        theme = "onedark";
        flavour = "dark";
        accent = "blue";

        transparent = true;
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

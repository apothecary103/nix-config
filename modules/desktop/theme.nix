{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      # CelestialCrafter's river rice: Rosé Pine Dawn, opaque, rose for focus.
      orchard = {
        enable = true;
        theme = "rose-pine";
        flavour = "dawn";
        accent = "rose";
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

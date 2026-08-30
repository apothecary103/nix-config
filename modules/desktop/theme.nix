{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      orchard = {
        enable = true;
        theme = "catppuccin";
        flavour = "macchiato";
        accent = "blue";

        transparent = true;
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

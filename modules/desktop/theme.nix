{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      # Sakura: hand-tuned soft greys and a calm pink, for every program
      # orchard themes and the shell.
      orchard = {
        enable = true;
        theme = "sakura";
        flavour = "night";
        accent = "pink";
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      # Material You from the wallpaper (matugen): every program orchard
      # themes, the shell included, takes its roles from the same image.
      orchard = {
        enable = true;
        theme = "matugen";
        flavour = "dark";
        accent = "primary";
        matugen.image = ../../assets/botanical-shop.png;
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };
}

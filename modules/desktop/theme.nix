{ inputs, ... }:
let
  wearing = {
    theme = "catppuccin";
    flavour = "macchiato";
    accent = "blue";
  };
in
{
  flake.modules.hjem.base =
    { config, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      orchard = wearing // {
        enable = true;

        transparent = true;
      };

      # Shorter names for the hand-styled configs orchard covers no port for.
      _module.args.palette = config.orchard.palette;
      _module.args.theme = config.orchard;
    };

  # The virtual console, which is system-level rather than per-user.
  flake.modules.nixos.base = {
    imports = [ inputs.orchard.nixosModules.default ];

    orchard = wearing // {
      enable = true;
    };
  };
}

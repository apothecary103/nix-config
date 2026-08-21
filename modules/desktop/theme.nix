{ inputs, ... }:
let
  # One binding for both classes, so the console cannot drift away from the
  # user's tree.
  wearing = {
    theme = "evergarden";
    flavour = "fall";
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

        # Ghostty runs with a translucent background, so every port that can
        # skip painting its own should.
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

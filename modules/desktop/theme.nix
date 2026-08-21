{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, pkgs, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      orchard = {
        enable = true;
        theme = "gruvbox";
        # flavour = if pkgs.stdenv.hostPlatform.isDarwin then "macchiato" else "mocha";
        flavour = "dark-hard";
        accent = "blue";

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

    orchard = {
      enable = true;
      theme = "catppuccin";
      accent = "blue";
    };
  };
}

{ inputs, ... }:
{
  flake.modules.hjem.base =
    { config, pkgs, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      orchard = {
        enable = true;
        theme = "catppuccin";
        flavour = if pkgs.stdenv.hostPlatform.isDarwin then "macchiato" else "mocha";
        accent = "blue";

        # No theme here ships a transparent variant, so the editor drops its
        # background and reads the terminal's instead.
        helix.transparent = true;
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

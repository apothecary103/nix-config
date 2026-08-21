{ inputs, ... }:
let
  active = "catppuccin";

  # Only the active theme's block is written; orchard leaves the other six
  # disabled. Flipping `active` is the whole switch.
  settings =
    isDarwin:
    {
      adwaita = {
        flavour = "dark";
        accent = "blue";
      };

      catppuccin = {
        flavour = if isDarwin then "macchiato" else "mocha";
        accent = "blue";
      };

      evergarden = {
        flavour = "fall";
        accent = "green";
      };

      gruvbox = {
        flavour = "dark";
        accent = "aqua";
      };

      gruvbox-material = {
        flavour = "dark";
        accent = "green";
      };

      luna.accent = "blue";

      onedark = {
        flavour = "dark";
        accent = "blue";
      };
    }
    .${active};
in
{
  flake.modules.hjem.base =
    { config, pkgs, ... }:
    {
      imports = [ inputs.orchard.hjemModules.default ];

      ${active} = settings pkgs.stdenv.hostPlatform.isDarwin // {
        enable = true;

        # No theme here ships a transparent variant, so the editor drops its
        # background and reads the terminal's instead.
        helix.transparent = true;
      };

      # Raw hex, for the hand-styled configs no port covers — niri, quickshell,
      # the tmux status line, rmpc's layout, hyprlock.
      _module.args.palette = config.${active}.palette;

      # The active theme's own option tree, so the modules that have to name a
      # theme (btop's color_theme, zellij's theme, tmux's source-file) can read
      # it without knowing which of the seven is on.
      _module.args.theme = config.${active};
    };

  # The virtual console, which is system-level rather than per-user.
  flake.modules.nixos.base = {
    imports = [ inputs.orchard.nixosModules.default ];

    ${active} = settings false // {
      enable = true;
    };
  };
}

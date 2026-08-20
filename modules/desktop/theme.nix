{ inputs, ... }:
{
  flake.modules.hjem.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      active = "catppuccin";

      flavor = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";

      onCatppuccin = lib.mkIf (active == "catppuccin");

      # The hand-styled configs were written against catppuccin's names. These
      # four have no counterpart in the ports, so they borrow the nearest hue;
      # every other name is spelled the same in all three palettes.
      compat =
        p:
        p
        // {
          mauve = p.purple;
          lavender = p.blue;
          sapphire = p.skye;
          sky = p.skye;
        };

      palettes = {
        catppuccin = config.catppuccin.palette;
        evergarden = compat config.evergarden.palette;
        luna = compat config.luna.palette;
      };

      helixTheme = config.catppuccin.helix.themeName;
    in
    {
      imports = [
        inputs.catppuccin.hjemModules.default
        inputs.evergarden.hjemModules.default
        inputs.luna.hjemModules.default
      ];

      evergarden = {
        enable = active == "evergarden";
        flavor = "fall";
        accent = "green";
        helix.transparent = true;
      };

      luna = {
        enable = active == "luna";
        accent = "blue";
        helix.transparent = true;

        # Its port hardcodes solid backgrounds on every status-bar style;
        # term/tmux.nix styles the bar itself and wants it transparent.
        tmux.enable = false;
      };

      catppuccin = {
        enable = active == "catppuccin";
        autoEnable = true;
        inherit flavor;
        accent = "blue";
      };

      # Raw hex, for the hand-styled configs no port covers.
      _module.args.palette = palettes.${active};

      # The active port's own options, so the modules that have to name a theme
      # (btop's color_theme, zellij's theme, tmux's source-file) can read it
      # without knowing which of the three is on.
      _module.args.theme = config.${active};

      # catppuccin ships no transparent variant, so re-export its theme with the
      # background dropped — helix reads "no bg" as the terminal's. `inherits`
      # also pulls in the palette that `fg` resolves against.
      rum.programs.helix = {
        themes = onCatppuccin {
          "${helixTheme}-transparent" = {
            inherits = helixTheme;
            "ui.background".fg = "text";
          };
        };
        settings.theme = onCatppuccin (lib.mkForce "${helixTheme}-transparent");
      };
    };
}

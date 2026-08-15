{ inputs, ... }:
{
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # The one switch: the enables, the palette and every themed program follow it.
      active = "luna";

      flavor = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";

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
        catppuccin = lib.mapAttrs (_: color: color.hex) (
          (lib.importJSON "${inputs.catppuccin-palette}/palette.json").${flavor}.colors
        );
        evergarden = compat config.evergarden.palette;
        luna = compat config.luna.palette;
      };
    in
    {
      imports = [
        inputs.catppuccin.homeModules.catppuccin
        inputs.evergarden.homeModules.default
        inputs.luna.homeModules.default
      ];

      evergarden = {
        enable = active == "evergarden";
        flavor = "fall";
        accent = "green";
      };

      luna = {
        enable = active == "luna";
        accent = "blue";
      };

      catppuccin = {
        enable = active == "catppuccin";
        autoEnable = true;
        inherit flavor;
        accent = "blue";

        nushell.enable = false;
        mpv.enable = false;
        librewolf.enable = false;

        # gtk.nix sets Adwaita; without this catppuccin forces Papirus-Dark and
        # the two fight over gtk.iconTheme.name.
        gtk.icon.enable = false;
      };

      # Raw hex, for the hand-styled configs no theme module covers.
      _module.args.palette = palettes.${active};
    };
}

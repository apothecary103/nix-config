{ inputs, ... }:
{
  flake.modules.homeManager.base =
    {
      lib,
      pkgs,
      ...
    }:
    let
      flavor = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";
    in
    {
      imports = [ inputs.catppuccin.homeModules.catppuccin ];

      catppuccin = {
        enable = true;
        autoEnable = true;
        inherit flavor;
        accent = "blue";

        helix.enable = false;
        nushell.enable = false;
        mpv.enable = false;
        librewolf.enable = false;

        # gtk.nix sets Adwaita; without this catppuccin forces Papirus-Dark and
        # the two fight over gtk.iconTheme.name.
        gtk.icon.enable = false;
      };

      # Raw hex, for the hand-styled configs the catppuccin module doesn't cover.
      _module.args.palette = lib.mapAttrs (_: color: color.hex) (
        (lib.importJSON "${inputs.catppuccin-palette}/palette.json").${flavor}.colors
      );
    };
}

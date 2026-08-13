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
      imports = [
        inputs.catppuccin.homeModules.catppuccin
        inputs.evergarden.homeModules.default
        inputs.luna.homeModules.default
      ];

      # Imported so switching is one `enable` away; only one of the three may be
      # on at a time, since they all write the same program themes.
      evergarden = {
        enable = false;
        flavor = "fall";
        accent = "green";
      };

      luna = {
        enable = false;
        accent = "blue";
      };

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

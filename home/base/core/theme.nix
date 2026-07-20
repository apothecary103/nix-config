{ inputs, pkgs, lib, ... }:

let
  # Every themed app follows these two lines. `flavor` can be any of latte,
  # frappe, macchiato, mocha; a non-catppuccin scheme only needs `palette`
  # rebound to an attrset with the same colour names.
  flavor = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";
  accent = "blue";

  palette = (lib.importJSON "${inputs.catppuccin-palette}/palette.json").${flavor};
in
{
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    autoEnable = true;
    inherit flavor accent;

    # hand-themed via the `theme` arg below; their ports would double-theme
    ghostty.enable = false;
    helix.enable = false;
    mako.enable = false;
    rofi.enable = false;
    tmux.enable = false;
    waybar.enable = false;
    wezterm.enable = false;

    nushell.enable = false;
  };

  _module.args.theme = rec {
    inherit flavor;
    colors = lib.mapAttrs (_: c: c.hex) palette.colors;
    accentColor = colors.${accent};
    slug = "catppuccin_${flavor}";
    title = "Catppuccin ${palette.name}";
  };
}

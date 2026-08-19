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
        catppuccin = lib.mapAttrs (_: color: color.hex) (
          (lib.importJSON "${inputs.catppuccin-palette}/palette.json").${flavor}.colors
        );
        evergarden = compat config.evergarden.palette;
        luna = compat config.luna.palette;
      };

      helixTheme = "catppuccin-${config.catppuccin.helix.flavor}";

      # catppuccin's own yazi module writes theme.toml, which is where yazi.nix's
      # overrides live, so its theme is repackaged as a flavor instead — yazi
      # layers preset < flavor < theme.toml. evergarden and luna ship a flavor.
      yaziFlavor = "catppuccin-${flavor}";
      yaziFlavorPkg = pkgs.runCommand "yazi-flavor-${yaziFlavor}" { } ''
        mkdir -p $out
        cp ${config.catppuccin.sources.yazi}/${flavor}/${yaziFlavor}-${config.catppuccin.accent}.toml $out/flavor.toml
        cp "${config.catppuccin.sources.bat}/Catppuccin ${lib.toSentenceCase flavor}.tmTheme" $out/tmtheme.xml
      '';
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
        yazi.enable = false;

        # gtk.nix sets Adwaita; without this catppuccin forces Papirus-Dark and
        # the two fight over gtk.iconTheme.name.
        gtk.icon.enable = false;
      };

      # Raw hex, for the hand-styled configs no theme module covers.
      _module.args.palette = palettes.${active};

      programs.helix = {
        evergarden.transparent = true;
        luna.transparent = true;

        # catppuccin/nix ships no transparent variant, so re-export its theme
        # with the background dropped — helix reads "no bg" as the terminal's.
        # `inherits` also pulls in the palette that `fg` resolves against.
        themes = onCatppuccin {
          "${helixTheme}-transparent" = {
            inherits = helixTheme;
            "ui.background".fg = "text";
          };
        };
        settings.theme = onCatppuccin (lib.mkForce "${helixTheme}-transparent");
      };

      # Its port hardcodes solid backgrounds on every status-bar style; tmux.nix
      # styles the bar itself and wants it transparent.
      programs.tmux.luna.enable = false;

      programs.yazi = {
        flavors = onCatppuccin { ${yaziFlavor} = yaziFlavorPkg; };
        theme.flavor = onCatppuccin {
          dark = yaziFlavor;
          light = yaziFlavor;
        };
      };
    };
}

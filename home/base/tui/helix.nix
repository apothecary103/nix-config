{ inputs, pkgs, ... }:

let
  # Mirrors the flavor choice in ../core/theme.nix (darwin -> macchiato, else -> mocha)
  flavor = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";
in
{
  programs.helix = {
    enable = true;
    defaultEditor = true;
    package = inputs.helix.packages.${pkgs.system}.default;

    themes = {
      "catppuccin_${flavor}_transparent" = {
        inherits = "catppuccin_${flavor}";
        "ui.background" = {
          bg = "none";
        };
      };
    };

    settings = {
      theme = "catppuccin_${flavor}_transparent";

      editor = {
        true-color = true;
        line-number = "relative";
        mouse = false;
        cursorline = true;
        bufferline = "multiple";
        default-line-ending = "lf";
        lsp.display-messages = true;

        cursor-shape = {
          insert = "bar";
          select = "underline";
        };

        file-picker = {
          hidden = false;
          git-ignore = true;
        };

        soft-wrap = {
          enable = true;
        };
      };
    };
  };
}

{ inputs, pkgs, theme, ... }:
{
  programs.helix = {
    enable = true;
    defaultEditor = true;
    package = inputs.helix.packages.${pkgs.system}.default;

    themes = {
      catppuccin_transparent = {
        inherits = theme.slug;
        "ui.background" = {
          bg = "none";
        };
      };
    };

    settings = {
      theme = "catppuccin_transparent";

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

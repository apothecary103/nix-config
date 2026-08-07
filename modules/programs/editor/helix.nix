{ inputs, ... }: {
  flake.modules.homeManager.base =
    { config, pkgs, ... }:
    let
      inherit (config.catppuccin) flavor;
    in
    {
      programs.helix = {
        enable = true;
        defaultEditor = true;
        package = inputs.helix.packages.${pkgs.stdenv.hostPlatform.system}.default;

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

        # Per-language LSP config lives in each project's .helix/languages.toml
        # (scaffolded by templates/), not here.
      };
    };
}

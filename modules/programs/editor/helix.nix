{ inputs, ... }: {
  flake.modules.homeManager.base =
    { pkgs, ... }:
    let
      flavour = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";
    in
    {
      programs.helix = {
        enable = true;
        defaultEditor = true;
        package = inputs.helix.packages.${pkgs.system}.default;

        themes = {
          "catppuccin_${flavour}_transparent" = {
            inherits = "catppuccin_${flavour}";
            "ui.background" = {
              bg = "none";
            };
          };
        };

        settings = {
          theme = "catppuccin_${flavour}_transparent";

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

        # Per-language LSP config now lives in each project's
        # .helix/languages.toml, scaffolded by the devShell templates under
        # templates/ (nix flake init -t ~/nix-config#{rust,python,web}). Only
        # nix is handled globally, via helix's built-in defaults + nixd on PATH.
      };
    };
}

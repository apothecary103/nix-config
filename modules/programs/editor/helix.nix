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
        languages = {
          language = [
            {
              name = "python";
              auto-format = true;
              language-servers = [
                "ty"
                "ruff"
              ];
            }
            {
              name = "rust";
              auto-format = true;
              language-servers = [ "rust-analyzer" ];
            }
            {
              name = "tsx";
              auto-format = true;
              language-servers = [
                "typescript-language-server"
                "tailwindcss-ls"
              ];
            }
            {
              name = "jsx";
              auto-format = true;
              language-servers = [
                "typescript-language-server"
                "tailwindcss-ls"
              ];
            }
            {
              name = "typescript";
              auto-format = true;
              language-servers = [
                "typescript-language-server"
                "tailwindcss-ls"
              ];
            }
            {
              name = "javascript";
              auto-format = true;
              language-servers = [
                "typescript-language-server"
                "tailwindcss-ls"
              ];
            }
            {
              name = "css";
              auto-format = true;
              language-servers = [
                "vscode-css-language-server"
                "tailwindcss-ls"
              ];
            }
            {
              name = "html";
              auto-format = true;
              language-servers = [
                "vscode-html-language-server"
                "tailwindcss-ls"
              ];
            }
          ];
        };
      };
    };
}

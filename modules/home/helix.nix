{inputs, ...}: {
  flake.modules.homeManager.base = {pkgs, ...}: let
    flavour =
      if pkgs.stdenv.isDarwin
      then "macchiato"
      else "mocha";
  in {
    programs.helix = {
      enable = true;
      defaultEditor = true;
      package = inputs.helix.packages.${pkgs.system}.default;

      languages = {
        language = [
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = "${pkgs.alejandra}/bin/alejandra";
              args = ["--quiet"];
            };
          }
        ];
      };

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
    };
  };
}

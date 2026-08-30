{ inputs, ... }:
{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      rum.programs.helix = {
        enable = true;

        package = inputs.steelix.packages.${pkgs.system}.helix.overrideAttrs (previous: {
          cargoBuildFeatures = (previous.cargoBuildFeatures or [ ]) ++ [ "steel" ];
        });

        settings = {
          editor = {
            true-color = true;
            line-number = "relative";
            color-modes = true;
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

            soft-wrap.enable = true;
          };

          keys = {
            normal = {
              # Buffer navigation
              "A-h" = "goto_previous_buffer";
              "A-l" = "goto_next_buffer";

              space.q = ":buffer-close";

              # Syntax-tree navigation
              tab = "move_parent_node_end";
              "S-tab" = "move_parent_node_start";

              # Subword navigation
              "A-w" = "move_next_sub_word_start";
              "A-b" = "move_prev_sub_word_start";
              "A-e" = "move_next_sub_word_end";
            };

            insert = {
              "S-tab" = "move_parent_node_start";
            };

            select = {
              # Syntax-tree selection
              tab = "extend_parent_node_end";
              "S-tab" = "extend_parent_node_start";

              # Subword selection.
              "A-w" = "extend_next_sub_word_start";
              "A-b" = "extend_prev_sub_word_start";
              "A-e" = "extend_next_sub_word_end";
            };
          };
        };

        # Keep language/LSP configuration project-local.
        #
        # .helix/languages.toml is scaffolded by templates/.
      };

      # Steel resolves helix.scm relative to init.scm, so both files must exist
      # even when no Steel configuration is needed yet.
      xdg.config.files = {
        "helix/helix.scm".text = "";
        "helix/init.scm".text = "";
      };

      # rum currently has no `defaultEditor` option.
      environment.sessionVariables = {
        EDITOR = "hx";
        VISUAL = "hx";
      };
    };
}

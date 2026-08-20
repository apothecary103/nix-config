{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      rum.programs.helix = {
        enable = true;
        package = pkgs.steelix;

        settings.editor = {
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

          soft-wrap.enable = true;
        };

        # Per-language LSP config lives in each project's .helix/languages.toml,
        # scaffolded by templates/.
      };

      # rum has no `defaultEditor`.
      environment.sessionVariables = {
        EDITOR = "hx";
        VISUAL = "hx";
      };
    };
}

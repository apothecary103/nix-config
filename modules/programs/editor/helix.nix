{ inputs, ... }: {
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.helix = {
        enable = true;
        defaultEditor = true;
        package = inputs.helix.packages.${pkgs.stdenv.hostPlatform.system}.default;

        # The theme itself comes from whichever module desktop/theme.nix has
        # active; only the see-through background is ours.
        evergarden.transparent = true;
        luna.transparent = true;

        settings = {
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

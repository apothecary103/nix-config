{ ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = true;
    
    themes = {
      catppuccin_macchiato_transparent = {
        inherits = "catppuccin_macchiato";
        "ui.background" = { bg = "none"; };
      };
    };

    settings = {
      theme = "catppuccin_macchiato_transparent";

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

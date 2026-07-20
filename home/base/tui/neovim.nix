{ pkgs, inputs, ... }:

{
  imports = [ inputs.nvf.homeManagerModules.default ];

  programs.nvf = {
    enable = true;

    settings = {
      vim = {
        options = {
          number = true;
          relativenumber = true;
          signcolumn = "yes";
          cursorline = true;
          cursorlineopt = "both";

          tabstop = 4;
          shiftwidth = 4;
          expandtab = true;
          swapfile = false;
          termguicolors = true;

          scrolloff = 5;

          wrap = true;
          linebreak = true;
          breakindent = true;
          showbreak = "↪ ";
          fillchars = "eob: ";

          undofile = true;
          ignorecase = true;
          smartcase = true;
          updatetime = 250;
          timeoutlen = 300;
          splitright = true;
          splitbelow = true;
          mouse = "a";
        };

        theme = {
          enable = true;
          name = "catppuccin";
          style = "macchiato";
          transparent = true;
        };

        binds.whichKey.enable = true;
        telescope.enable = true;
        comments.comment-nvim.enable = true;
        notes.todo-comments.enable = true;
        git.gitsigns.enable = true;
        utility.oil-nvim.enable = true;
        autocomplete.blink-cmp.enable = true;

        visuals = {
          nvim-web-devicons.enable = true;
          fidget-nvim.enable = true;
        };

        lsp = {
          enable = true;
          formatOnSave = true;
        };

        treesitter.enable = true;

        languages = {
          enableTreesitter = true;
          nix.enable = true;
        };
      };
    };
  };
}

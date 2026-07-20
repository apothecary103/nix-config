{
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.nvf.homeManagerModules.default];

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
          mouse = ""; # helix: editor.mouse = false

          # helix cursor shapes: block in normal, bar in insert,
          # underline in select/visual
          guicursor = "n-c-sm:block,i-ci-ve:ver25,v:hor20,r-cr:hor20,o:hor50";
        };

        theme = {
          enable = true;
          name = "catppuccin";
          style =
            if pkgs.stdenv.isDarwin
            then "macchiato"
            else "mocha";
          transparent = true;
        };

        extraPlugins = {
          aylin-vim = {
            package = pkgs.vimPlugins.aylin-vim;
          };
        };

        telescope = {
          enable = true;
          setupOpts.defaults.borderchars = ["─" "│" "─" "│" "┌" "┐" "┘" "└"];
        };

        binds.whichKey = {
          enable = true;
          setupOpts = {
            preset = "helix";
          };
        };

        comments.comment-nvim.enable = true;
        notes.todo-comments.enable = true;
        git.gitsigns.enable = true;
        utility.oil-nvim.enable = true;
        autocomplete.blink-cmp.enable = true;

        # helix: editor.bufferline = "multiple" — only show the bufferline
        # when more than one buffer is open
        tabline.nvimBufferline = {
          enable = true;
          setupOpts.options.always_show_bufferline = false;
        };

        # helix's statusline equivalent; follows the active colorscheme
        statusline.lualine.enable = true;

        visuals = {
          nvim-web-devicons.enable = true;
          fidget-nvim.enable = true;
        };

        lsp = {
          enable = true;
          formatOnSave = true;
        };

        treesitter = {
          enable = true;
          # helix bundles every grammar; installing them all also makes the
          # comment-hint injections (/* toml */ ''...'' etc.) highlight the
          # embedded language, exactly like helix does
          grammars = pkgs.vimPlugins.nvim-treesitter.allGrammars;
        };

        languages = {
          enableTreesitter = true;
          nix.enable = true;
        };

        # helix highlights purely via tree-sitter — neovim layers LSP
        # semantic tokens on top by default, which recolors identifiers and
        # breaks 1:1 color parity, so strip them on attach
        luaConfigRC.no-semantic-tokens = ''
          vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(args)
              local client = vim.lsp.get_client_by_id(args.data.client_id)
              if client then
                client.server_capabilities.semanticTokensProvider = nil
              end
            end,
          })
        '';
      };
    };
  };
}

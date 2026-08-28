{ inputs, ... }:
let
  bind = mode: key: action: desc: {
    inherit
      mode
      key
      action
      desc
      ;
  };

  neovim = {
    programs.nvf = {
      enable = true;
      enableManpages = true;

      # Helix owns EDITOR/VISUAL; see editor/helix.nix.
      defaultEditor = false;

      settings.vim = {
        viAlias = true;
        vimAlias = true;
        enableLuaLoader = true;

        globals = {
          mapleader = " ";
          maplocalleader = " ";
        };

        # Prefer nvf's intent-level options where it has them.
        lineNumberMode = "relNumber";
        searchCase = "smart";
        preventJunkFiles = true;
        undoFile.enable = true;

        options = {
          cursorline = true;
          signcolumn = "yes";
          scrolloff = 8;
          sidescrolloff = 8;
          wrap = false;

          splitbelow = true;
          splitright = true;
          splitkeep = "screen";
          jumpoptions = "stack";

          inccommand = "split";
          confirm = true;
          updatetime = 250;
          timeoutlen = 300;
          pumheight = 12;
          termguicolors = true;
          winborder = "single";

          # Keep Neovim's built-in per-window status line and command-line mode
          # indicator. Do not set 'statusline': Neovim supplies the layout.
          laststatus = 2;
          showmode = true;
          showcmd = true;
          ruler = true;
        };

        theme = {
          enable = true;
          name = "catppuccin";
          style = "macchiato";
          transparent = true;
        };

        ui.borders = {
          enable = true;
          globalStyle = "single";
        };

        visuals = {
          nvim-web-devicons.enable = true;
          fidget-nvim.enable = true;
        };

        diagnostics = {
          enable = true;
          config = {
            severity_sort = true;
            update_in_insert = false;
            signs = true;
            virtual_text = {
              spacing = 2;
              source = "if_many";
            };
            float = {
              border = "single";
              source = "if_many";
            };
            jump.float = true;
          };
        };

        fzf-lua = {
          enable = true;
          profile = "default-title";
          setupOpts = {
            fzf_colors = true;
            winopts = {
              height = 0.85;
              width = 0.85;
              preview = {
                layout = "flex";
                scrollbar = false;
              };
            };
            files.formatter = "path.filename_first";
            grep.rg_glob = true;
          };
        };

        autocomplete.blink-cmp = {
          enable = true;

          # Blink's upstream "default" preset follows native completion:
          # C-n/C-p select, C-y accepts, and Tab remains snippet navigation.
          setupOpts.keymap.preset = "default";
          mappings = {
            complete = null;
            confirm = null;
            next = null;
            previous = null;
            close = null;
            scrollDocsUp = null;
            scrollDocsDown = null;
          };
        };

        git.gitsigns.enable = true;

        binds.whichKey = {
          enable = true;
          setupOpts = {
            preset = "modern";
            delay = 300;
          };
          register = {
            "<leader>s" = "+Search";
            "<leader>c" = "+Code";
            "<leader>u" = "+Toggle";
            "gs" = "+Surround";
          };
        };

        utility.oil-nvim = {
          enable = true;
          setupOpts = {
            delete_to_trash = true;
            watch_for_changes = true;
            view_options = {
              show_hidden = true;
              natural_order = "fast";
            };
          };
        };

        # Surround is the only editing grammar added here. Keeping it below
        # `gs` preserves Neovim's native `s` substitute command.
        mini.surround = {
          enable = true;
          setupOpts.mappings = {
            add = "gsa";
            delete = "gsd";
            find = "gsf";
            find_left = "gsF";
            highlight = "gsh";
            replace = "gsr";
            update_n_lines = "";
          };
        };

        lsp = {
          enable = true;
          formatOnSave = true;
          lightbulb.enable = false;
          trouble.enable = false;

          # Neovim already provides K, gra, gri, grn, grr, grt, gO,
          # CTRL-S, [d and ]d. Only fill the gaps and add format controls.
          mappings = {
            goToDefinition = "gd";
            goToDeclaration = "gD";
            goToType = null;
            listImplementations = null;
            listReferences = null;
            nextDiagnostic = null;
            previousDiagnostic = null;
            openDiagnosticFloat = null;
            documentHighlight = null;
            listDocumentSymbols = null;
            addWorkspaceFolder = null;
            removeWorkspaceFolder = null;
            listWorkspaceFolders = null;
            listWorkspaceSymbols = null;
            hover = null;
            signatureHelp = null;
            renameSymbol = null;
            codeAction = null;
            format = "<leader>cf";
            toggleFormatOnSave = "<leader>uf";
          };
        };

        # Language servers and formatters come from each project's dev shell.
        # These definitions teach Neovim how to launch commands from PATH while
        # keeping treesitter grammars in the editor closure.
        lsp.servers = {
          nixd = {
            enable = true;
            cmd = [ "nixd" ];
            filetypes = [ "nix" ];
            root_markers = [
              "flake.nix"
              ".git"
            ];
          };
          bash-language-server = {
            enable = true;
            cmd = [
              "bash-language-server"
              "start"
            ];
            filetypes = [
              "bash"
              "sh"
            ];
            root_markers = [ ".git" ];
          };
          lua-language-server = {
            enable = true;
            cmd = [ "lua-language-server" ];
            filetypes = [ "lua" ];
            root_markers = [
              ".luarc.json"
              ".luarc.jsonc"
              ".git"
            ];
          };
          marksman = {
            enable = true;
            cmd = [
              "marksman"
              "server"
            ];
            filetypes = [ "markdown" ];
            root_markers = [
              ".marksman.toml"
              ".git"
            ];
          };
          vscode-json-language-server = {
            enable = true;
            cmd = [
              "vscode-json-language-server"
              "--stdio"
            ];
            filetypes = [
              "json"
              "jsonc"
            ];
            root_markers = [ ".git" ];
          };
          yaml-language-server = {
            enable = true;
            cmd = [
              "yaml-language-server"
              "--stdio"
            ];
            filetypes = [ "yaml" ];
            root_markers = [ ".git" ];
          };
          taplo = {
            enable = true;
            cmd = [
              "taplo"
              "lsp"
              "stdio"
            ];
            filetypes = [ "toml" ];
            root_markers = [ ".git" ];
          };
          ty = {
            enable = true;
            cmd = [
              "ty"
              "server"
            ];
            filetypes = [ "python" ];
            root_markers = [
              "pyproject.toml"
              ".git"
            ];
          };
          rust-analyzer = {
            enable = true;
            cmd = [ "rust-analyzer" ];
            filetypes = [ "rust" ];
            root_markers = [
              "Cargo.toml"
              ".git"
            ];
          };
          gopls = {
            enable = true;
            cmd = [ "gopls" ];
            filetypes = [
              "go"
              "gomod"
              "gosum"
              "gowork"
              "gotmpl"
            ];
            root_markers = [
              "go.work"
              "go.mod"
              ".git"
            ];
          };
          typescript-language-server = {
            enable = true;
            cmd = [
              "typescript-language-server"
              "--stdio"
            ];
            filetypes = [
              "javascript"
              "typescript"
            ];
            root_markers = [
              "package.json"
              "tsconfig.json"
              ".git"
            ];
          };
          svelte-language-server = {
            enable = true;
            cmd = [
              "svelteserver"
              "--stdio"
            ];
            filetypes = [ "svelte" ];
            root_markers = [
              "package.json"
              ".git"
            ];
          };
          vscode-html-language-server = {
            enable = true;
            cmd = [
              "vscode-html-language-server"
              "--stdio"
            ];
            filetypes = [
              "html"
              "xhtml"
            ];
            root_markers = [
              "package.json"
              ".git"
            ];
          };
          vscode-css-language-server = {
            enable = true;
            cmd = [
              "vscode-css-language-server"
              "--stdio"
            ];
            filetypes = [
              "css"
              "less"
              "scss"
            ];
            root_markers = [
              "package.json"
              ".git"
            ];
          };
          tailwindcss-language-server = {
            enable = true;
            cmd = [
              "tailwindcss-language-server"
              "--stdio"
            ];
            filetypes = [
              "html"
              "css"
              "scss"
              "javascript"
              "typescript"
              "svelte"
            ];
            root_markers = [
              "tailwind.config.js"
              "tailwind.config.ts"
              "package.json"
              ".git"
            ];
          };
          zls = {
            enable = true;
            cmd = [ "zls" ];
            filetypes = [
              "zig"
              "zir"
            ];
            root_markers = [
              "build.zig"
              ".git"
            ];
          };
        };

        languages = {
          enableFormat = false;
          enableTreesitter = true;
          enableExtraDiagnostics = false;

          nix = {
            enable = true;
            lsp.enable = false;
          };
          bash = {
            enable = true;
            lsp.enable = false;
          };
          lua = {
            enable = true;
            lsp.enable = false;
          };
          markdown = {
            enable = true;
            lsp.enable = false;
          };
          json = {
            enable = true;
            lsp.enable = false;
          };
          yaml = {
            enable = true;
            lsp.enable = false;
          };
          toml = {
            enable = true;
            lsp.enable = false;
          };
          python = {
            enable = true;
            lsp.enable = false;
          };
          rust = {
            enable = true;
            lsp.enable = false;
          };
          go = {
            enable = true;
            lsp.enable = false;
          };
          typescript = {
            enable = true;
            lsp.enable = false;
          };
          svelte = {
            enable = true;
            lsp.enable = false;
          };
          html = {
            enable = true;
            lsp.enable = false;
          };
          css = {
            enable = true;
            lsp.enable = false;
          };
          zig = {
            enable = true;
            lsp.enable = false;
          };
        };

        keymaps = [
          (bind "n" "<Esc>" "<cmd>nohlsearch<CR>" "Clear search highlight")
          (bind "n" "-" "<cmd>Oil<CR>" "Open parent directory")

          # A small, stable picker surface. The global picker searches files by
          # default; prefix its query with $, @, or # for buffers and symbols.
          (bind "n" "<leader><space>" "<cmd>FzfLua global<CR>" "Find anything")
          (bind "n" "<leader>," "<cmd>FzfLua buffers<CR>" "Find buffer")
          (bind "n" "<leader>/" "<cmd>FzfLua live_grep_native<CR>" "Grep project")
          (bind "n" "<leader>:" "<cmd>FzfLua command_history<CR>" "Command history")
          (bind "n" "<leader>sr" "<cmd>FzfLua oldfiles<CR>" "Recent files")
          (bind "n" "<leader>sR" "<cmd>FzfLua resume<CR>" "Resume picker")
          (bind "n" "<leader>sd" "<cmd>FzfLua diagnostics_workspace<CR>" "Diagnostics")
          (bind "n" "<leader>sh" "<cmd>FzfLua helptags<CR>" "Help")
          (bind "n" "<leader>sk" "<cmd>FzfLua keymaps<CR>" "Keymaps")

          (bind "n" "<C-h>" "<C-w><C-h>" "Focus left window")
          (bind "n" "<C-j>" "<C-w><C-j>" "Focus lower window")
          (bind "n" "<C-k>" "<C-w><C-k>" "Focus upper window")
          (bind "n" "<C-l>" "<C-w><C-l>" "Focus right window")
          (bind "x" "<" "<gv" "Indent left")
          (bind "x" ">" ">gv" "Indent right")
        ];
      };
    };
  };
in
{
  flake.modules.nixos.base.imports = [
    inputs.nvf.nixosModules.nvf
    neovim
  ];

  flake.modules.darwin.base.imports = [
    inputs.nvf.darwinModules.nvf
    neovim
  ];
}

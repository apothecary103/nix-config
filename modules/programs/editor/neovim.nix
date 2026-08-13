{ config, inputs, ... }:
{
  imports = [ inputs.nix-wrapper-modules.flakeModules.wrappers ];

  flake.wrappers.neovim =
    {
      config,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.wrapperModules.neovim ];

      settings = {
        config_directory = ./nvim;
        aliases = [
          "vi"
          "vim"
        ];
      };

      # lze is the one plugin that has to be on the runtimepath before init.lua
      # runs; it packadds everything below out of the opt directory.
      specs.loader = pkgs.vimPlugins.lze;

      specs.plugins = {
        lazy = true;
        data = with pkgs.vimPlugins; [
          (config.nvim-lib.mkPlugin "luna.nvim" inputs.luna-nvim)
          (config.nvim-lib.mkPlugin "bg.nvim" inputs.bg-nvim)
          {
            # nixpkgs calls it evergarden-nvim, but `:colorscheme evergarden`
            # and so the name lze packadds is the bare word.
            pname = "evergarden";
            data = evergarden-nvim;
          }

          snacks-nvim
          oil-nvim
          which-key-nvim
          flash-nvim
          gitsigns-nvim
          conform-nvim

          blink-cmp
          friendly-snippets
          nvim-lspconfig
          lazydev-nvim
          fidget-nvim

          mini-icons
          mini-statusline
          mini-tabline
          mini-surround
          mini-ai
          mini-pairs
          mini-move

          # withPlugins hangs the grammars and their queries off `.dependencies`,
          # which the wrapper puts on the startup runtimepath and collates into a
          # single plugin.
          (nvim-treesitter.withPlugins (
            p: with p; [
              bash
              c
              comment
              css
              csv
              diff
              dockerfile
              fish
              git_config
              git_rebase
              gitattributes
              gitcommit
              gitignore
              go
              gomod
              html
              javascript
              json
              json5
              lua
              luadoc
              make
              markdown
              markdown_inline
              nix
              nu
              printf
              python
              query
              regex
              rust
              scss
              sql
              ssh_config
              svelte
              toml
              tsx
              typescript
              vim
              vimdoc
              xml
              yaml
              zig
            ]
          ))
          nvim-treesitter-textobjects
        ];
      };
    };

  flake.modules.homeManager.base = {
    imports = [ config.flake.wrappers.neovim.install ];

    wrappers.neovim.enable = true;
  };
}

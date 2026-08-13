{ inputs, ... }: {
  flake.modules.homeManager.base = { config, pkgs, ... }: {
    imports = [ inputs.nvf.homeManagerModules.default ];

    programs.nvf = {
      enable = false;

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
            mouse = "";

            # block in normal, bar in insert, underline in select/visual
            guicursor = "n-c-sm:block,i-ci-ve:ver25,v:hor20,r-cr:hor20,o:hor50";
          };

          # Base16 acts as the safety net for unmapped plugins
          theme = {
            enable = true;
            name = "base16";
            transparent = true;
            base16-colors = {
              base00 = "#19161b"; # Default Background
              base01 = "#201c23"; # Lighter Background
              base02 = "#27232b"; # Selection Background
              base03 = "#504957"; # Comments & Invisibles
              base04 = "#675f70"; # Dark Foreground
              base05 = "#e6dfdc"; # Default Foreground
              base06 = "#f0eaf2"; # Light Foreground
              base07 = "#f8f4f9"; # Light Background
              base08 = "#e882a8"; # Variables (Sakura Pink)
              base09 = "#a87678"; # Constants / Numbers (Dusty Red)
              base0A = "#d1cac7"; # Classes / Search (Soft Warm Grey)
              base0B = "#8ebd8f"; # Strings (Sage Green)
              base0C = "#738199"; # Support / Regex (Muted Blue-Gray)
              base0D = "#8779a8"; # Functions / Methods (Soft Purple)
              base0E = "#b294bb"; # Keywords / Storage (Mauve)
              base0F = "#a87678"; # Embedded Code
            };
          };

          extraPlugins = {
            aylin-vim = {
              package = pkgs.vimPlugins.aylin-vim;
            };
          };

          telescope = {
            enable = true;
            setupOpts.defaults.borderchars = [
              "─"
              "│"
              "─"
              "│"
              "┌"
              "┐"
              "┘"
              "└"
            ];
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
          utility.motion.flash-nvim.enable = true;
          autocomplete.blink-cmp.enable = true;

          ##########################################################
          ## Helix-like bufferline
          ##########################################################
          tabline.nvimBufferline = {
            enable = true;
            setupOpts.options = {
              mode = "buffers";
              numbers = "none";

              indicator.style = "none";
              modified_icon = "[+]";
              buffer_close_icon = "";
              close_icon = "";
              left_trunc_marker = "‹";
              right_trunc_marker = "›";

              show_buffer_icons = false;
              show_buffer_close_icons = false;
              show_close_icon = false;
              show_tab_indicators = false;
              color_icons = false;

              diagnostics = false;
              separator_style = [
                ""
                ""
              ];
              enforce_regular_tabs = false;
              tab_size = 0;
              max_name_length = 40;
              truncate_names = true;
              always_show_bufferline = false;
              hover.enabled = false;
            };
          };

          visuals = {
            nvim-web-devicons.enable = true;
            fidget-nvim = {
              enable = true;
              setupOpts = {
                progress = {
                  display = {
                    done_ttl = 2;
                    progress_icon = {
                      pattern = "dots";
                      period = 1;
                    };
                  };
                };
                notification = {
                  window = {
                    winblend = 0;
                  };
                };
              };
            };
          };

          mini = {
            pairs.enable = true;
            surround.enable = true;
            hipatterns.enable = true;
            ai.enable = true;
          };

          ##########################################################
          ## Helix modeline
          ##########################################################
          statusline.lualine = {
            enable = true;
            theme = "base16";
            icons.enable = false;
            globalStatus = false;
            componentSeparator = {
              left = "";
              right = "";
            };
            sectionSeparator = {
              left = "";
              right = "";
            };

            activeSection = {
              a = [
                "{ function() return _G.HelixLine.mode() end, padding = { left = 1, right = 1 }, }"
              ];
              b = [
                ''{ "filename", path = 0, symbols = { modified = "[+]", readonly = "[readonly]", unnamed = "[scratch]", newfile = "[+]" }, }''
              ];
              c = [ ];
              x = [
                ''{ function() local ok, fidget = pcall(require, "fidget") return ok and fidget.status() or "" end, }''
                ''{ "diagnostics", sources = { "nvim_diagnostic" }, symbols = { error = "● ", warn = "● ", info = "● ", hint = "● " }, }''
              ];
              y = [
                "{ function() return _G.HelixLine.selections() end }"
                "{ function() return _G.HelixLine.register() end }"
              ];
              z = [
                "{ function() return _G.HelixLine.position() end }"
                "{ function() return _G.HelixLine.encoding() end }"
              ];
            };

            inactiveSection = {
              a = [ ];
              b = [
                ''{ "filename", path = 0, symbols = { modified = "[+]", readonly = "[readonly]", unnamed = "[scratch]" }, }''
              ];
              c = [ ];
              x = [ ];
              y = [ ];
              z = [ "{ function() return _G.HelixLine.position() end }" ];
            };
          };

          lsp = {
            enable = true;
            formatOnSave = true;
          };

          treesitter = {
            enable = true;
          };

          languages = {
            enableTreesitter = true;
            nix.enable = true;
          };

          ##########################################################
          ## NvChad 1:1 Visual Parity + Perfect Treesitter Overrides
          ##########################################################
          luaConfigRC.nvchad-highlights = ''
            local function setup_nvchad_highlights()
              local c = {
                white = "#e6dfdc",
                darker_black = "#131115",
                black = "#19161b", 
                black2 = "#201c23",
                one_bg = "#27232b",
                one_bg2 = "#302b35",
                one_bg3 = "#3a3440",
                grey = "#453f4b",
                grey_fg = "#504957",
                grey_fg2 = "#5a5262",
                light_grey = "#675f70",
                red = "#a87678",
                baby_pink = "#f0a8c0",
                pink = "#e882a8",
                line = "#2d2832",
                green = "#8ebd8f",
                vibrant_green = "#9ed4a0",
                nord_blue = "#8779a8",
                blue = "#8779a8",
                yellow = "#d1cac7",
                sun = "#e6dfdc",
                purple = "#b294bb",
                dark_purple = "#8779a8",
                teal = "#738199",
                orange = "#a87678",
                cyan = "#70b8ba",
                statusline_bg = "#201c23",
                lightbg = "#27232b",
                pmenu_bg = "#e882a8",
                folder_bg = "#8779a8",
              }

              -- Respect config transparency for main window
              local bg_color = "NONE"

              local highlights = {
                -- Base UI
                Normal = { fg = c.white, bg = bg_color },
                NormalNC = { fg = c.white, bg = bg_color },
                SignColumn = { bg = bg_color },
                LineNr = { fg = c.grey },
                CursorLine = { bg = c.black2 },
                CursorLineNr = { fg = c.white, bg = bg_color },
                ColorColumn = { bg = c.black2 },
                Visual = { bg = c.one_bg2 },
                Search = { bg = c.green, fg = c.black },
                IncSearch = { bg = c.orange, fg = c.black },

                -- Floating Windows / PMenu (NvChad opaque dark style)
                NormalFloat = { bg = c.darker_black },
                FloatBorder = { fg = c.grey, bg = c.darker_black },
                Pmenu = { bg = c.one_bg },
                PmenuSel = { bg = c.pmenu_bg, fg = c.black },
                PmenuSbar = { bg = c.one_bg2 },
                PmenuThumb = { bg = c.grey },

                -- Standard Syntax
                Comment = { fg = c.grey_fg, italic = true },
                String = { fg = c.green },
                Number = { fg = c.orange },
                Float = { fg = c.orange },
                Boolean = { fg = c.orange },
                Identifier = { fg = c.white },
                Function = { fg = c.blue },
                Statement = { fg = c.purple },
                Keyword = { fg = c.purple },
                Conditional = { fg = c.purple },
                Repeat = { fg = c.purple },
                Operator = { fg = c.pink },
                PreProc = { fg = c.cyan },
                Type = { fg = c.yellow },
                Special = { fg = c.pink },
                Constant = { fg = c.orange },
                Delimiter = { fg = c.light_grey },
                Error = { fg = c.red },
                Warning = { fg = c.yellow },

                -- Perfect Treesitter Map (NvChad logic)
                ["@variable"] = { fg = c.white },
                ["@variable.builtin"] = { fg = c.red },
                ["@variable.parameter"] = { fg = c.white },
                ["@variable.member"] = { fg = c.teal },
                
                ["@function"] = { fg = c.blue },
                ["@function.builtin"] = { fg = c.red },
                ["@function.macro"] = { fg = c.teal },
                
                ["@keyword"] = { fg = c.purple },
                ["@keyword.operator"] = { fg = c.pink },
                ["@keyword.function"] = { fg = c.purple },
                ["@keyword.return"] = { fg = c.purple },
                ["@keyword.conditional"] = { fg = c.purple },
                
                ["@operator"] = { fg = c.pink },
                ["@string"] = { fg = c.green },
                ["@string.escape"] = { fg = c.pink },
                ["@string.regexp"] = { fg = c.cyan },
                
                ["@number"] = { fg = c.orange },
                ["@boolean"] = { fg = c.orange },
                
                ["@type"] = { fg = c.yellow },
                ["@type.builtin"] = { fg = c.yellow },
                
                ["@property"] = { fg = c.teal },
                
                ["@punctuation.bracket"] = { fg = c.light_grey },
                ["@punctuation.delimiter"] = { fg = c.light_grey },
                ["@punctuation.special"] = { fg = c.pink },
                
                ["@constant"] = { fg = c.orange },
                ["@constant.builtin"] = { fg = c.orange },
                ["@constant.macro"] = { fg = c.orange },
                
                ["@constructor"] = { fg = c.yellow },
                ["@comment"] = { fg = c.grey_fg, italic = true },
                ["@tag"] = { fg = c.purple },
                ["@tag.attribute"] = { fg = c.yellow },
                ["@tag.delimiter"] = { fg = c.light_grey },

                -- LSP Diagnostics
                DiagnosticError = { fg = c.red },
                DiagnosticWarn = { fg = c.yellow },
                DiagnosticInfo = { fg = c.green },
                DiagnosticHint = { fg = c.purple },
                
                -- Telescope (NvChad Borderless Style)
                TelescopeBorder = { fg = c.darker_black, bg = c.darker_black },
                TelescopePromptBorder = { fg = c.black2, bg = c.black2 },
                TelescopePromptNormal = { fg = c.white, bg = c.black2 },
                TelescopePromptPrefix = { fg = c.red, bg = c.black2 },
                TelescopeNormal = { bg = c.darker_black },
                TelescopePreviewTitle = { fg = c.black, bg = c.green },
                TelescopePromptTitle = { fg = c.black, bg = c.red },
                TelescopeResultsTitle = { fg = c.darker_black, bg = c.darker_black },
                TelescopeSelection = { bg = c.one_bg, fg = c.white },
                
                -- Oil Nvim (Acts like NvimTree)
                OilNormal = { bg = c.darker_black },
                OilNormalNC = { bg = c.darker_black },
              }

              for group, hl in pairs(highlights) do
                vim.api.nvim_set_hl(0, group, hl)
              end
            end

            -- Ensure highlights apply dynamically
            vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
              callback = function() vim.schedule(setup_nvchad_highlights) end,
            })
            vim.schedule(setup_nvchad_highlights)
          '';

          luaConfigRC.helix-ui = ''
            _G.HelixLine = {}

            local mode_map = {
              ["n"] = "NOR", ["no"] = "NOR", ["nov"] = "NOR", ["noV"] = "NOR",
              ["niI"] = "NOR", ["niR"] = "NOR", ["niV"] = "NOR",
              ["nt"] = "NOR", ["ntT"] = "NOR",
              ["c"] = "NOR", ["cv"] = "NOR", ["ce"] = "NOR",
              ["r"] = "NOR", ["rm"] = "NOR", ["r?"] = "NOR", ["!"] = "NOR",
              ["v"] = "SEL", ["vs"] = "SEL", ["V"] = "SEL", ["Vs"] = "SEL",
              ["\22"] = "SEL", ["\22s"] = "SEL",
              ["s"] = "SEL", ["S"] = "SEL", ["\19"] = "SEL",
              ["i"] = "INS", ["ic"] = "INS", ["ix"] = "INS",
              ["R"] = "INS", ["Rc"] = "INS", ["Rx"] = "INS",
              ["Rv"] = "INS", ["Rvc"] = "INS", ["Rvx"] = "INS",
              ["t"] = "INS",
            }

            function HelixLine.mode() return mode_map[vim.api.nvim_get_mode().mode] or "NOR" end

            function HelixLine.selections()
              local m = vim.api.nvim_get_mode().mode
              local n = 1
              if m == "V" or m == "S" or m == "\22" or m == "\19" then
                n = math.abs(vim.fn.line("v") - vim.fn.line(".")) + 1
              end
              if n == 1 then return "1 sel" end
              return n .. " sels"
            end

            function HelixLine.register()
              local r = vim.fn.reg_recording()
              if r ~= "" then return "reg=" .. r end
              return ""
            end

            function HelixLine.position() return vim.fn.line(".") .. ":" .. vim.fn.charcol(".") end

            function HelixLine.encoding()
              local e = vim.bo.fileencoding
              if e ~= "" and e:lower() ~= "utf-8" then return e end
              return ""
            end

            function HelixLine.highlights()
              local c = {
                white = "#e6dfdc", darker_black = "#131115",
                black = "#19161b", black2 = "#201c23",
                one_bg = "#27232b", grey = "#453f4b",
                grey_fg2 = "#5a5262", red = "#a87678",
                green = "#8ebd8f", blue = "#8779a8",
                yellow = "#d1cac7", purple = "#b294bb",
                orange = "#a87678", statusline_bg = "#201c23"
              }
              local set = vim.api.nvim_set_hl

              local status_bg = c.statusline_bg
              local status_nc_bg = c.darker_black

              set(0, "StatusLine", { fg = c.white, bg = status_bg })
              set(0, "StatusLineNC", { fg = c.grey_fg2, bg = status_nc_bg })

              local modes = {
                normal   = c.blue,
                insert   = c.green,
                visual   = c.purple,
                replace  = c.red,
                command  = c.yellow,
                terminal = c.green,
              }

              for mode, colour in pairs(modes) do
                set(0, "lualine_a_" .. mode, { fg = c.black, bg = colour, bold = true })
                set(0, "lualine_b_" .. mode, { fg = c.white, bg = status_bg })
                set(0, "lualine_c_" .. mode, { fg = c.white, bg = status_bg })
                set(0, "lualine_x_" .. mode, { fg = c.grey_fg2, bg = status_bg })
                set(0, "lualine_y_" .. mode, { fg = c.white, bg = status_bg })
                set(0, "lualine_z_" .. mode, { fg = c.white, bg = status_bg })
              end

              local inactives = { "a", "b", "c", "x", "y", "z" }
              for _, sec in ipairs(inactives) do
                set(0, "lualine_" .. sec .. "_inactive", { fg = c.grey_fg2, bg = status_nc_bg })
              end

              -- Bufferline
              set(0, "BufferLineFill", { bg = "NONE" })
              set(0, "BufferLineBackground", { fg = c.grey_fg2, bg = "NONE" })
              set(0, "BufferLineBufferVisible", { fg = c.grey, bg = "NONE" })
              set(0, "BufferLineBufferSelected", { fg = c.white, bg = "NONE", bold = true, italic = false })
              set(0, "BufferLineDuplicate", { fg = c.grey_fg2, bg = "NONE" })
              set(0, "BufferLineDuplicateVisible", { fg = c.grey, bg = "NONE" })
              set(0, "BufferLineDuplicateSelected", { fg = c.white, bg = "NONE", bold = true })
              set(0, "BufferLineModified", { fg = c.yellow, bg = "NONE" })
              set(0, "BufferLineModifiedVisible", { fg = c.yellow, bg = "NONE" })
              set(0, "BufferLineModifiedSelected", { fg = c.yellow, bg = "NONE" })
              set(0, "BufferLineSeparator", { fg = "NONE", bg = "NONE" })
              set(0, "BufferLineSeparatorVisible", { fg = "NONE", bg = "NONE" })
              set(0, "BufferLineSeparatorSelected", { fg = "NONE", bg = "NONE" })
              set(0, "BufferLineIndicatorSelected", { fg = "NONE", bg = "NONE" })
              set(0, "BufferLineIndicatorVisible", { fg = "NONE", bg = "NONE" })
              set(0, "BufferLineTruncMarker", { fg = c.grey_fg2, bg = "NONE" })
              set(0, "BufferLineTabClose", { fg = "NONE", bg = "NONE" })
            end

            vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
              callback = function() vim.schedule(HelixLine.highlights) end,
            })
            vim.schedule(HelixLine.highlights)
          '';
        };
      };
    };
  };
}

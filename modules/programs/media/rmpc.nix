{ inputs, ... }: {
  flake.modules.homeManager.base =
    {
      config,
      pkgs,
      rmpcLib,
      palette,
      ...
    }:
    let
      # The palette arg already follows the per-platform catppuccin flavor
      # (theme.nix), so just name the theme accordingly.
      flavour = if pkgs.stdenv.isDarwin then "macchiato" else "mocha";
      inherit (rmpcLib)
        variant
        enum
        struct
        pane
        prop
        text
        tab
        ;
      bold = fg: {
        inherit fg;
        modifiers = "Bold";
      };

      inherit (palette)
        mauve
        lavender
        sapphire
        yellow
        base
        mantle
        overlay0
        ;
      fgText = palette.text;
    in
    {
      imports = [ inputs.rmpc.homeManagerModules.default ];

      programs.rmpc = {
        enable = true;

        settings = {
          address = "127.0.0.1:6600";
          theme = "catppuccin-${flavour}";
          lyrics_dir = "${config.home.homeDirectory}/.lyrics";

          album_art = {
            method = variant "Auto";
            max_size_px = {
              width = 0;
              height = 0;
            };
            vertical_align = variant "Top";
          };

          tabs = [
            {
              name = "Queue";
              pane = struct "Split" {
                direction = variant "Horizontal";
                panes = [
                  {
                    size = "100%";
                    pane = pane "Queue";
                  }
                  {
                    size = "42";
                    pane = struct "Split" {
                      direction = variant "Vertical";
                      panes = [
                        {
                          size = "20";
                          borders = "TOP | BOTTOM";
                          pane = pane "AlbumArt";
                        }
                        {
                          size = "100%";
                          borders = "NONE";
                          pane = pane "Lyrics";
                        }
                      ];
                    };
                  }
                ];
              };
            }
            (tab "Directories" "Directories")
            (tab "Artists" "Artists")
            (tab "Album Artists" "AlbumArtists")
            (tab "Albums" "Albums")
            (tab "Playlists" "Playlists")
            (tab "Search" "Search")
          ];
        };

        themes."catppuccin-${flavour}" = {
          default_album_art_path = null;
          symbols = {
            song = "🎵";
            dir = "📁";
            playlist = "🎼";
            marker = "";
          };

          layout = struct "Split" {
            direction = variant "Vertical";
            panes = [
              {
                pane = pane "Header";
                size = "1";
              }
              {
                pane = pane "TabContent";
                size = "100%";
              }
              {
                pane = pane "ProgressBar";
                size = "1";
              }
            ];
          };

          progress_bar = {
            symbols = [
              ""
              ""
              "⭘"
              " "
              " "
            ];
            track_style = {
              bg = mantle;
            };
            elapsed_style = {
              fg = mauve;
              bg = mantle;
            };
            thumb_style = {
              fg = mauve;
              bg = mantle;
            };
          };

          scrollbar = {
            symbols = [
              "│"
              "█"
              "▲"
              "▼"
            ];
            track_style = { };
            ends_style = { };
            thumb_style = {
              fg = lavender;
            };
          };

          browser_column_widths = [
            20
            38
            42
          ];
          text_color = fgText;
          background_color = base;
          header_background_color = mantle;
          modal_background_color = null;
          modal_backdrop = false;

          tab_bar = {
            active_style = {
              fg = "black";
              bg = mauve;
              modifiers = "Bold";
            };
            inactive_style = { };
          };
          borders_style = {
            fg = overlay0;
          };
          highlighted_item_style = {
            fg = mauve;
            bg = null;
            modifiers = "Bold";
          };
          current_item_style = {
            fg = "black";
            bg = lavender;
            modifiers = "Bold";
          };
          highlight_border_style = {
            fg = lavender;
          };

          song_table_format = [
            {
              prop = {
                kind = prop (variant "Artist");
                style = {
                  fg = lavender;
                };
                default = {
                  kind = text "Unknown";
                };
              };
              width = "50%";
              alignment = variant "Right";
            }
            {
              prop = {
                kind = text "-";
                style = {
                  fg = lavender;
                };
                default = {
                  kind = text "Unknown";
                };
              };
              width = "1";
              alignment = variant "Center";
            }
            {
              prop = {
                kind = prop (variant "Title");
                style = {
                  fg = sapphire;
                };
                default = {
                  kind = text "Unknown";
                };
              };
              width = "50%";
            }
          ];

          lyrics = {
            timestamp = false;
            alignment = variant "Center";
          };

          header.rows = [
            {
              left = [
                {
                  kind = text "[";
                  style = bold lavender;
                }
                {
                  kind = prop (enum "Status" [ (variant "State") ]);
                  style = bold lavender;
                }
                {
                  kind = text "]";
                  style = bold lavender;
                }
              ];
              center = [
                {
                  kind = prop (enum "Song" [ (variant "Artist") ]);
                  style = bold yellow;
                  default = {
                    kind = text "Unknown";
                    style = bold yellow;
                  };
                }
                { kind = text " - "; }
                {
                  kind = prop (enum "Song" [ (variant "Title") ]);
                  style = bold sapphire;
                  default = {
                    kind = text "No Song";
                    style = bold sapphire;
                  };
                }
              ];
              right = [
                {
                  kind = text "Vol: ";
                  style = bold lavender;
                }
                {
                  kind = prop (enum "Status" [ (variant "Volume") ]);
                  style = bold lavender;
                }
                {
                  kind = text "% ";
                  style = bold lavender;
                }
              ];
            }
          ];
        };
      };
    };
}

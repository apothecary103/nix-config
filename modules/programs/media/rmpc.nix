{
  flake.modules.hjem.base =
    {
      config,
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      # rmpc reads RON, which has no Nix builtin. Four shapes appear below that
      # JSON cannot express: unit variants (`Horizontal`), newtype variants
      # (`Pane(Queue)`), struct variants (`Split(direction: …)`) and `None`.
      variant = name: { _unit = name; };
      call = name: args: {
        _call = name;
        _args = args;
      };
      struct = name: fields: call name [ fields ];
      pane = name: call "Pane" [ (variant name) ];
      prop = value: call "Property" [ value ];
      text = value: call "Text" [ value ];

      toRON =
        let
          go =
            indent: value:
            let
              inner = indent + "  ";
              body =
                attrs:
                lib.concatMapStringsSep ",\n" (name: "${inner}${name}: ${go inner attrs.${name}}") (
                  builtins.attrNames attrs
                );
              isPlainAttrs = v: builtins.isAttrs v && !(v ? _unit) && !(v ? _call);
            in
            if value == null then
              "None"
            else if builtins.isBool value then
              lib.boolToString value
            else if builtins.isInt value then
              toString value
            else if builtins.isString value then
              builtins.toJSON value
            else if builtins.isList value then
              if value == [ ] then
                "[]"
              else
                "[\n${lib.concatMapStringsSep ",\n" (e: inner + go inner e) value}\n${indent}]"
            else if value ? _unit then
              value._unit
            else if value ? _call then
              # A lone struct argument is spliced in rather than nested, which is
              # what `unwrap_variant_newtypes` in the prelude expects to see.
              if builtins.length value._args == 1 && isPlainAttrs (builtins.head value._args) then
                "${value._call}(\n${body (builtins.head value._args)}\n${indent})"
              else
                "${value._call}(${lib.concatMapStringsSep ", " (go indent) value._args})"
            else if value == { } then
              "()"
            else
              "(\n${body value}\n${indent})";
        in
        value: ''
          #![enable(implicit_some)]
          #![enable(unwrap_newtypes)]
          #![enable(unwrap_variant_newtypes)]
          ${go "" value}
        '';

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

      tab = name: paneName: {
        inherit name;
        pane = pane paneName;
      };

      settings = {
        address = "127.0.0.1:6600";
        theme = "custom";
        lyrics_dir = "${config.directory}/.lyrics";

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

      theme = {
        default_album_art_path = null;
        symbols = {
          song = "🎵";
          dir = "📁";
          playlist = "🎼";
          marker = "";
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
            ""
            ""
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
                kind = prop (call "Status" [ (variant "State") ]);
                style = bold lavender;
              }
              {
                kind = text "]";
                style = bold lavender;
              }
            ];
            center = [
              {
                kind = prop (call "Song" [ (variant "Artist") ]);
                style = bold yellow;
                default = {
                  kind = text "Unknown";
                  style = bold yellow;
                };
              }
              { kind = text " - "; }
              {
                kind = prop (call "Song" [ (variant "Title") ]);
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
                kind = prop (call "Status" [ (variant "Volume") ]);
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
    in
    {
      packages = [ pkgs.rmpc ];

      xdg.config.files = {
        "rmpc/config.ron".text = toRON settings;
        "rmpc/themes/custom.ron".text = toRON theme;
      };
    };
}

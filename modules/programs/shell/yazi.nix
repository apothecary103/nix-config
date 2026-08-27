{
  flake.modules.hjem.base =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      # The statusline: one solid bar, uniform text, no bold anywhere. The two
      # colours are the theme's own modeline pair rather than a step off the
      # ramp, so this reads the way the same theme's statusline does elsewhere.
      bar = {
        fg = palette.statusFg;
        bg = palette.statusBg;
        bold = false;
      };
    in
    {
      rum.programs.yazi = {
        enable = true;

        settings = {
          mgr = {
            sort_dir_first = true;
            ratio = [
              1
              4
              3
            ];
          };
          preview = {
            max_width = 3840;
            max_height = 2160;
            image_filter = "lanczos3";
            image_delay = 0;
          };
        };

        theme = {
          # MIME types are only fetched for the folder you're in, so in a preview
          # pane the flavor's mime rules match nothing and its files come out
          # uncoloured. Same colours keyed off the extension first, with the
          # flavor's mime rules kept after them. This replaces the flavor's list
          # outright — yazi swaps the whole array.
          filetype.rules = [
            {
              url = "*.{jpg,jpeg,png,gif,bmp,webp,avif,heic,heif,tif,tiff,ico,svg}";
              fg = palette.yellow;
            }
            {
              url = "*.{mp3,flac,wav,ogg,opus,m4a,aac,aiff,mp4,mkv,webm,mov,avi,m4v,wmv,flv}";
              fg = palette.pink;
            }
            {
              url = "*.{zip,rar,7z,tar,gz,tgz,xz,zst,bz2,lz4,lzma,iso,cpio,ar,deb,rpm}";
              fg = palette.red;
            }
            {
              url = "*.{pdf,doc,docx,rtf,odt,epub}";
              fg = palette.sky;
            }

            {
              mime = "image/*";
              fg = palette.yellow;
            }
            {
              mime = "{audio,video}/*";
              fg = palette.pink;
            }
            {
              mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}";
              fg = palette.red;
            }
            {
              mime = "application/{pdf,doc,rtf}";
              fg = palette.sky;
            }
            {
              mime = "vfs/{absent,stale}";
              fg = palette.surface1;
            }

            {
              url = "*";
              is = "orphan";
              bg = palette.red;
            }
            {
              url = "*";
              is = "exec";
              fg = palette.green;
            }
            {
              url = "*";
              is = "dummy";
              bg = palette.red;
            }
            {
              url = "*/";
              is = "dummy";
              bg = palette.red;
            }
            {
              url = "*/";
              fg = palette.blue;
            }
          ];

          mgr = {
            # A space, not "": an empty string falls back to yazi's "│".
            border_symbol = " ";
          };

          tabs = {
            active = {
              fg = palette.text;
              bg = "reset";
              bold = true;
            };
            inactive = {
              fg = palette.overlay1;
              bg = "reset";
            };

            # The preset's rounded powerline caps take their fg from the tab
            # backgrounds, which are "reset" above, so they'd paint as blobs in
            # the plain text colour. The tab names carry their own spaces.
            sep_inner = {
              open = "";
              close = "";
            };
            sep_outer = {
              open = "";
              close = "";
            };
          };

          mode = {
            normal_main = bar;
            normal_alt = bar;
            select_main = bar;
            select_alt = bar;
            unset_main = bar;
            unset_alt = bar;
          };

          status = {
            overall = bar;

            progress_label = {
              fg = palette.text;
              bold = false;
            };

            sep_left = {
              open = "";
              close = "";
            };
            sep_right = {
              open = "";
              close = "";
            };

            progress_normal = {
              fg = palette.green;
              bg = palette.mantle;
            };
          };
        };
      };

      # rum's yazi module has no initLua, and yazi loads this file itself.
      # The hovered row's "" / "" caps are styled apart from the row itself
      # (indicator.padding + Entity:style_rev), so swapping them for spaces in
      # the theme leaves those cells unstyled. Return plain padding that
      # inherits the row's own highlight instead.
      xdg.config.files."yazi/init.lua".text = # lua
        ''
          -- One more column of left padding on the file lists than the preset
          -- Tab:build gives them, so the hovered row's highlight — which
          -- ratatui fills across the whole list area — starts clear of the
          -- pane edge rather than flush against it.
          function Tab:build()
          	local c = self._chunks
          	local p = c[2].w > 0 and 0 or 1
          	self._children = {
          		Parent:new(c[1]:pad(ui.Pad(0, p, 0, 2)), self._tab),
          		Current:new(c[2]:pad(ui.Pad(0, 1, 0, 2)), self._tab),
          		Preview:new(c[3]:pad(ui.Pad(0, 1, 0, p)), self._tab),
          		Rails:new(c, self._tab),
          		Markers:new(c, self._tab),
          	}
          end

          -- Hover in the current pane takes its background from the entry's
          -- own colour — directory blue, image yellow, executable green —
          -- instead of the flavor's one fixed accent. Files with only a
          -- background rule of their own (orphans, dummies) have no fg to
          -- borrow, so they fall back to the plain text colour.
          function Entity:style()
          	local s = self._file:style() or ui.Style()
          	if not self._file.is_hovered then
          		return s
          	end
          	return ui.Style():bg(s:fg() or "${palette.text}"):fg("${palette.base}")
          end

          -- Markers are drawn at the chunk's own left edge, which the padding
          -- above pushed away from the rows; shift them over so a selection
          -- bar sits flush against the entry it marks.
          function Markers:build()
          	self._children = {
          		Marker:new(self._chunks[1]:pad(ui.Pad.left(1)), self._tab.parent),
          		Marker:new(self._chunks[2]:pad(ui.Pad.left(1)), self._tab.current),
          	}
          end

          function Entity:padding() return " " end

          function Linemode:padding()
          	if not self._file.is_hovered then
          		return " "
          	end
          	return ui.Span(" "):style(Entity:new(self._file):style())
          end

          -- Size after the file name in the status bar, not before it. Ids 2
          -- and 3 are the preset's own "length" and "name" children.
          Status:children_remove(2, Status.LEFT)
          Status:children_add(function(self) return ui.Line { "  ", Status.length(self) } end, 4000, Status.LEFT)
        '';

      # Replaces the wrapper home-manager generated from `shellWrapperName`: cd
      # to wherever yazi was left when it exits.
      rum.programs.fish.functions.yy = # fish
        ''
          set -l tmp (mktemp -t yazi-cwd.XXXXXX)
          command yazi $argv --cwd-file="$tmp"
          if set -l cwd (command cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
              builtin cd -- "$cwd"
          end
          rm -f -- "$tmp"
        '';

      rum.programs.zsh.initConfig = # bash
        ''
          yy() {
            local tmp; tmp="$(mktemp -t yazi-cwd.XXXXXX)"
            command yazi "$@" --cwd-file="$tmp"
            local cwd; cwd="$(command cat -- "$tmp")"
            [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
            rm -f -- "$tmp"
          }
        '';
    };
}

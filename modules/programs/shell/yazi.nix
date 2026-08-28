{
  flake.modules.hjem.base =
    {
      lib,
      palette,
      ...
    }:
    let
      # The statusline: one solid bar, uniform text, no bold anywhere. The two
      # colours are the theme's own modeline pair rather than a step off the
      # ramp, so this reads the way the same theme's statusline does elsewhere.
      bar = {
        fg = palette.statusBar.foreground;
        bg = palette.statusBar.background;
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
              fg = palette.hue.yellow;
            }
            {
              url = "*.{mp3,flac,wav,ogg,opus,m4a,aac,aiff,mp4,mkv,webm,mov,avi,m4v,wmv,flv}";
              fg = palette.hue.pink;
            }
            {
              url = "*.{zip,rar,7z,tar,gz,tgz,xz,zst,bz2,lz4,lzma,iso,cpio,ar,deb,rpm}";
              fg = palette.hue.red;
            }
            {
              url = "*.{pdf,doc,docx,rtf,odt,epub}";
              fg = palette.hue.skye;
            }

            {
              mime = "image/*";
              fg = palette.hue.yellow;
            }
            {
              mime = "{audio,video}/*";
              fg = palette.hue.pink;
            }
            {
              mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}";
              fg = palette.hue.red;
            }
            {
              mime = "application/{pdf,doc,rtf}";
              fg = palette.hue.skye;
            }
            {
              mime = "vfs/{absent,stale}";
              fg = palette.surface.neutral1;
            }

            {
              url = "*";
              is = "orphan";
              bg = palette.hue.red;
            }
            {
              url = "*";
              is = "exec";
              fg = palette.hue.green;
            }
            {
              url = "*";
              is = "dummy";
              bg = palette.hue.red;
            }
            {
              url = "*/";
              is = "dummy";
              bg = palette.hue.red;
            }
            {
              url = "*/";
              fg = palette.hue.blue;
            }
          ];

          mgr = {
            # A space, not "": an empty string falls back to yazi's "│".
            border_symbol = " ";
          };

          tabs = {
            active = {
              fg = palette.surface.text;
              bg = "reset";
              bold = true;
            };
            inactive = {
              fg = palette.surface.neutral4;
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
            # Match Catppuccin Macchiato in Helix: normal is rosewater, insert
            # is green, and select is lavender. Yazi's unset state occupies
            # the equivalent third slot. Only the mode badge changes colour;
            # its percentage and item count retain the shared statusline style.
            normal_main = {
              fg = palette.surface.background;
              bg = palette.ui.cursor;
              bold = true;
            };
            normal_alt = bar;
            select_main = {
              fg = palette.surface.background;
              bg = palette.ui.secondaryAccent;
              bold = true;
            };
            select_alt = bar;
            unset_main = {
              fg = palette.surface.background;
              bg = palette.hue.red;
              bold = true;
            };
            unset_alt = bar;
          };

          status = {
            overall = bar;

            progress_label = {
              fg = palette.surface.text;
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
              fg = palette.hue.green;
              bg = palette.surface.panel;
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
          	return ui.Style():bg(s:fg() or "${palette.surface.text}"):fg("${palette.surface.background}")
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

          -- Keep the mode pill separate from the item position. Yazi's preset
          -- gives both the same `*_main` style, so without this the right-side
          -- `n/n` counter inherits the pill's coloured background.
          function Status:position()
          	local cursor = self._current.cursor
          	local length = #self._current.files
          	local style = th.status.overall

          	return ui.Line {
          		ui.Span(th.status.sep_right.open):style(style),
          		ui.Span(string.format(" %2d/%-2d ", math.min(cursor + 1, length), length)):style(style),
          		ui.Span(th.status.sep_right.close):style(style),
           }
          end

          -- Helix gives each modeline field the same visual breathing room.
          -- Match the three-cell gaps already used on the left of this bar:
          -- mode → filename → size, then permissions → percentage → position.
          function Status:percent()
          	local cursor = self._current.cursor
          	local length = #self._current.files
          	local percent = cursor ~= 0 and length ~= 0 and math.floor((cursor + 1) * 100 / length) or 0
          	local text = percent == 0 and "Top" or percent == 100 and "Bot" or string.format("%2d%%", percent)
          	local style = self:style().alt

          	return ui.Line {
          		ui.Span("   " .. th.status.sep_right.open):fg(style:bg()),
          		ui.Span(text .. "  "):style(style),
          	}
          end

          -- The preset puts one space before the hovered filename; leave one
          -- more cell between the mode pill and the filename.
          function Status:name()
          	local hovered = self._current.hovered
          	if not hovered then
          		return ""
          	end
          	return "  " .. ui.printable(hovered.name)
          end

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

      rum.programs.nushell.extraConfig =
        lib.mkAfter # nu
          ''
            def --env yy [...args] {
              let tmp = (^mktemp -t yazi-cwd.XXXXXX | str trim)
              try {
                ^yazi ...$args --cwd-file $tmp
                let cwd = (open $tmp | str trim)
                if ($cwd | is-not-empty) and $cwd != $env.PWD {
                  cd $cwd
                }
              } finally {
                ^rm -f $tmp
              }
            }
          '';
    };
}

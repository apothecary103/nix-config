{
  flake.modules.homeManager.base = { pkgs, ... }: {
    programs.wezterm = {
      enable = true;

      extraConfig = /* lua */ ''
        local wezterm = require "wezterm"
        local config = wezterm.config_builder()

        -- Theme
        config.color_scheme = "${
          if pkgs.stdenv.isDarwin then "Catppuccin Macchiato" else "Catppuccin Mocha"
        }"

        -- Typography
        config.font = wezterm.font("Maple Mono NF CN", { weight = "Medium" })
        config.font_size = 18
        config.front_end = "OpenGL"
        -- Unhinted grayscale to match the macOS-like system rendering.
        -- HorizontalLcd forces subpixel AA → colour fringing on a 2x panel.
        config.freetype_load_flags = "NO_HINTING"
        config.cell_width = 0.9

        -- Window
        config.window_background_opacity = 0.93
        config.window_decorations = "TITLE|RESIZE"
        config.window_padding = {
          left = 20,
          right = 20,
          top = 20,
          bottom = 10,
        }

        -- Tabs
        config.hide_tab_bar_if_only_one_tab = true
        config.use_fancy_tab_bar = false

        -- Miscellaneous
        config.scrollback_lines = 5000

        return config
      '';
    };
  };
}

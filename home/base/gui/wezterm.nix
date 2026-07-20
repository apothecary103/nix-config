{ ... }:

{
  programs.wezterm = {
    enable = true;

    # colorSchemes = {
    #   mellow = {
    #     foreground = "#c9c7cd";
    #     background = "#161617";
    #     cursor_bg = "#e3e2e5";
    #     cursor_border = "#e3e2e5";
    #     cursor_fg = "#161617";
    #     selection_bg = "#3c3b3e";
    #     selection_fg = "#e3e2e5";
    #     scrollbar_thumb = "#57575f";
    #     split = "#57575f";
    #     ansi = [
    #       "#27272a" "#f5a191" "#90b99f" "#e6b99d" 
    #       "#aca1cf" "#e29eca" "#ea83a5" "#c1c0d4"
    #     ];
    #     brights = [
    #       "#353539" "#ffae9f" "#9dc6ac" "#f0c5a9" 
    #       "#b9aeda" "#ecaad6" "#f591b2" "#cac9dd"
    #     ];
    #   };
    # };

    extraConfig = ''
      local wezterm = require 'wezterm'
      local config = wezterm.config_builder()

      config.window_decorations = "TITLE | RESIZE"
      config.window_padding = {
        left = "24px",
        right = "24px",
        top = "16px",
        bottom = "16px",
      }

      config.font = wezterm.font('Maple Mono NF CN')
      config.font_size = 12
      config.color_scheme = "Catppuccin Macchiato"
      config.window_background_opacity = 1

      config.hide_tab_bar_if_only_one_tab = true
      config.use_fancy_tab_bar = false

      config.scrollback_lines = 5000

      return config
    '';
  };
}

{ ... }: {
  programs.zellij = {
    enable = true;
    settings = {
      pane_frames = false;
      simplified_ui = false;
      default_layout = "compact";
      theme = "catppuccin-macchiato";

      # copy_command = "pbcopy";
      copy_on_select = true;
      scroll_buffer_size = 10000;
      ui = {
        pane_frames = {
          rounded_corners = false;
        };
      };
    };
  };
}

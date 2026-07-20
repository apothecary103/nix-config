{ ... }:
{
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableNushellIntegration = true;
    shellWrapperName = "yy";
    settings = {
      mgr = {
        show_hidden = true;
        sort_dir_first = true;
        ratio = [ 1 4 3 ];
      };
      preview = {
        max_width = 3840;
        max_height = 2160;
        image_filter = "lanczos3";
      };
    };
  };
}

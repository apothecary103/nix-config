{
  flake.modules.homeManager.base = {
    programs.yazi = {
      enable = true;
      enableFishIntegration = true;
      shellWrapperName = "yy";

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
    };
  };
}

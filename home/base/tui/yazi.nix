{ config, inputs, ... }:
{
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];
  
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableNushellIntegration = true;
    shellWrapperName = "yy";
    settings = {
      mgr = {
        show_hidden = true;
        sort_dir_first = true;
      };
    };
  };

  catppuccin.yazi = {
    enable = true;
    flavor = "macchiato";
    accent = "blue";
  };
}

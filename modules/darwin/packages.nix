{ pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
      rustup
    
      # GUI Applications 
      yabai
      skhd
      jankyborders
      sketchybar
      aerospace
      # emacs-unstable
    ];
  };
}

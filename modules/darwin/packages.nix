{ pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
    
      # GUI Applications 
      aseprite
      yabai
      skhd
    ];
  };
}

{ pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
    
      # GUI Applications 
      yabai
      skhd
    ];
  };
}

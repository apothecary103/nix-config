{ pkgs, username, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
      ripgrep
      fd
      yazi
      eza
      aria2
      fastfetch
      chafa
      zellij
      wget
    
      # GUI Applications 
      prismlauncher
      signal-desktop
      vesktop
      mpv
      # cinny-desktop
    ];
  };
}

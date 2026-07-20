{ pkgs, username, inputs, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # CLI Tools
      ripgrep
      fd
      aria2
      fastfetch
      chafa
      wget
      ffmpeg
      broot
      btop
      nixd
      nixfmt
      gh
      bat
      tokei
      nh
      krabby
      opencode
    
      # GUI Applications 
      prismlauncher
      signal-desktop
      vesktop
      mpv
      inputs.zen-browser.packages."${pkgs.system}".default
    ];
  };
}

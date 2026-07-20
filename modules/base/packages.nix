{ pkgs, username, inputs, ... }:

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
      ffmpeg
      broot
      btop
      nixd
      nixfmt
      gh
      bat
      tokei
      tmux
      nh
      krabby
      opencode
      fd
      comma
    
      # GUI Applications 
      prismlauncher
      signal-desktop
      vesktop
      mpv
      inputs.zen-browser.packages."${pkgs.system}".default
      # cinny-desktop
    ];
  };
}

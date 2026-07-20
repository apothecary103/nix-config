{ pkgs, ... }:

{
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
    cinny-desktop
    
    # Fonts (See next section for more font config)
    maple-mono.NF-CN
    aporetic
  ];
}

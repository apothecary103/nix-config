{inputs, ...}: {
  flake.modules.homeManager.base = {pkgs, ...}: {
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
      alejandra
      gh
      bat
      tokei
      nh
      krabby
      opencode
      claude-code

      # GUI Applications
      prismlauncher
      signal-desktop
      vesktop
      mpv
      inputs.zen-browser.packages."${pkgs.system}".default
    ];
  };
}

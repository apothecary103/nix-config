{
  flake.modules.homeManager.base = { pkgs, ... }: {
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
      tokei
      krabby
      claude-code
      glow
      util-linux

      # GUI Applications
      prismlauncher
      signal-desktop
      vesktop
    ];
  };

  flake.modules.homeManager.darwin = { pkgs, ... }: {
    home.packages = with pkgs; [
      llama-cpp
      qemu
    ];
  };
}

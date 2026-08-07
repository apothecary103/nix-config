{
  flake.modules.homeManager.base = { pkgs, ... }: {
    home.packages = with pkgs; [
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

      prismlauncher
      signal-desktop
      vesktop
    ];
  };

  flake.modules.homeManager.darwin = { pkgs, ... }: {
    home.packages = with pkgs; [
      llama-cpp
      qemu
      aseprite
    ];
  };
}

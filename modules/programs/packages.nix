{ inputs, ... }: {
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
      nh
      krabby
      opencode
      claude-code
      glow

      # GUI Applications
      prismlauncher
      signal-desktop
      vesktop
      inputs.zen-browser.packages."${pkgs.system}".default
    ];
  };

  flake.modules.homeManager.darwin = { pkgs, ... }: {
    home.packages = with pkgs; [
      # CLI Tools
      llama-cpp
      qemu

      # GUI Applications
      aseprite
      # steam
      # moonlight-qt
    ];
  };
}

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
      nil
      nixfmt
      gh
      tokei
      krabby
      claude-code
      glow
      util-linux
      tree-sitter
      imagemagick

      # Editor tooling: language servers and formatters nvim expects on PATH
      # everywhere, rather than per-project. Anything that needs a project's own
      # dependency tree (ruff, ty, tsserver, svelte, rust-analyzer) stays in the
      # dev shell templates instead.
      lua-language-server
      stylua
      shfmt
      taplo
      prettierd
      nu-lint
      nufmt

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
      moonlight-qt
    ];
  };
}

{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      packages = with pkgs; [
        ripgrep
        fd
        aria2
        fastfetch
        chafa
        wget
        ffmpeg
        broot
        nixd
        nixfmt
        gh
        tokei
        krabby
        claude-code
        glow
        util-linux
        tree-sitter
        imagemagick

        prismlauncher
        signal-desktop
        vesktop
      ];
    };

  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = with pkgs; [
        llama-cpp
        qemu
        aseprite
        moonlight-qt
      ];
    };
}

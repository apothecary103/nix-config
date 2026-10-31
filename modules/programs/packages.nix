{ inputs, ... }:
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
        # Claude Code from numtide's llm-agents, which tracks releases daily.
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
        pi-coding-agent
        glow
        util-linux
        tree-sitter
        imagemagick

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
        blender
        moonlight-qt
        openlogi
      ];
    };
}

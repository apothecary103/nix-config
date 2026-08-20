{
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    {
      rum.programs.zsh = {
        enable = true;

        plugins = {
          # Ordering matters: syntax highlighting has to be the last plugin to
          # hook the line editor, so it is sourced after autosuggestions.
          autosuggestions.source = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh";
          syntax-highlighting.source = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
        };

        initConfig = lib.mkBefore ''
          autoload -Uz compinit && compinit
        '';
      };
    };
}

{
  flake.modules.hjem.base = {
    rum.programs.fzf = {
      enable = true;
      integrations = {
        fish.enable = true;
        zsh.enable = true;
      };
    };

    # The port writes the full palette into $FZF_DEFAULT_OPTS_FILE; fzf reads
    # that first and this second, so the two backgrounds stay the terminal's.
    environment.sessionVariables.FZF_DEFAULT_OPTS = "--color=bg:-1,bg+:-1";
  };
}

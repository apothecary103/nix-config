{
  flake.modules.hjem.base.rum.programs.direnv = {
    enable = true;
    integrations = {
      nix-direnv.enable = true;
      fish.enable = true;
      zsh.enable = true;
      nushell.enable = true;
    };

    # "-" is direnv's own spelling of "say nothing".
    settings.global.log_format = "-";
  };
}

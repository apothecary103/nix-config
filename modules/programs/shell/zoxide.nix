{
  flake.modules.hjem.base.rum.programs.zoxide = {
    enable = true;
    flags = [
      "--cmd"
      "cd"
    ];
    integrations = {
      fish.enable = true;
      zsh.enable = true;
      nushell.enable = true;
    };
  };
}

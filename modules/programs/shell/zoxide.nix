{
  flake.modules.hjem.base.rum.programs.zoxide = {
    enable = true;
    flags = [
      "--cmd"
      "cd"
    ];
    integrations = {
      fish.enable = true;
      nushell.enable = true;
    };
  };
}

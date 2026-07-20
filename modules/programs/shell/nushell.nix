{
  flake.modules.homeManager.base = {
    programs.nushell.enable = true;

    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
    };
  };
}

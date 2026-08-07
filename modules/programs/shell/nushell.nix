{
  flake.modules.homeManager.base = {
    programs.nushell = {
      enable = true;
      shellAliases = {
        cal = "cal --week-start=mo";
      };
    };

    programs.carapace.enable = true;
  };
}

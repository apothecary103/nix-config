{
  flake.modules.homeManager.base = {
    programs.man = {
      enable = true;
      generateCaches = false;
    };
  };
}

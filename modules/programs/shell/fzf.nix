{
  flake.modules.homeManager.base.programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    colors = {
      bg = "-1";
      "bg+" = "-1";
    };
  };
}

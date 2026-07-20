{
  flake.modules.homeManager.base.programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };
}

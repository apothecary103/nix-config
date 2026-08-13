{
  flake.modules.homeManager.base = {
    # A bare package in home.packages gets no theme, since every theme module
    # hangs its config off programs.btop.
    programs.btop.enable = true;
  };
}

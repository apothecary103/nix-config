{
  flake.modules.homeManager.base = {
    programs.man = {
      enable = true;
      generateCaches = false;
    };

    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANROFFOPT = "-c";
    };
  };
}

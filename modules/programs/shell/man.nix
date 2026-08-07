{
  flake.modules.homeManager.base = {
    programs.man = {
      enable = true;
      generateCaches = false;
    };

    # bat as the man pager (its batman/batgrep wrappers come from bat.nix).
    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANROFFOPT = "-c";
    };
  };
}

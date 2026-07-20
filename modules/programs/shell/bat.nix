{
  flake.modules.homeManager.base = { pkgs, ... }: {
    programs.bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batman
        batgrep
      ];
    };

    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANROFFOPT = "-c";
    };
  };
}

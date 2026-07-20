{
  flake.modules.homeManager.base = {pkgs, ...}: {
    programs.eza = {
      enable = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
      git = true;
      icons = "auto";
    };

    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
      options = ["--cmd cd"];
    };

    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
      colors = {
        bg = "-1";
        "bg+" = "-1";
      };
    };

    programs.bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [batman batgrep];
    };

    home.sessionVariables = {
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANROFFOPT = "-c";
    };
  };
}

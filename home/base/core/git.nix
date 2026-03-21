{ ... }: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name  = "apothecary";
        email = "113787039+apothecary103@users.noreply.github.com";
      };
      init.defaultBranch = "main";
    };
  };
}

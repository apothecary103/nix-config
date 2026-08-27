{
  flake.modules.hjem.base = {
    rum.programs.git = {
      enable = true;
      settings = {
        user = {
          name = "apothecary";
          email = "frieren@noreply.codeberg.org";
        };
        init.defaultBranch = "main";
      };
    };
  };
}

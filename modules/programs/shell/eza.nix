{
  flake.modules.homeManager.base.programs.eza = {
    enable = true;
    # The only one of these integrations home-manager defaults to false rather
    # than to home.shell.enableShellIntegration.
    enableNushellIntegration = true;
    git = true;
    icons = "auto";
  };
}

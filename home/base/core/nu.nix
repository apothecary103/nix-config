{ ... }:
{
  programs.eza = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.nushell = {
    enable = true;
  };
}

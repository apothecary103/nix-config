{
  flake.modules.hjem.base =
    {
      pkgs,
      ...
    }:
    {
      packages = [ pkgs.rmpc ];

      orchard.rmpc.enable = false;

      xdg.config.files = {
        "rmpc/config.ron".source = ./rmpc/config.ron;
        "rmpc/theme.ron".source = ./rmpc/theme.ron;
      };
    };
}

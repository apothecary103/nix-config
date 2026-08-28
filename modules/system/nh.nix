{ username, ... }:
let
  cleanArgs = [
    "--keep-since"
    "7d"
    "--keep"
    "5"
  ];
in
{
  flake.modules.nixos.base = {
    programs.nh = {
      enable = true;
      flake = "/home/${username}/nix-config";

      clean = {
        enable = true;
        extraArgs = builtins.concatStringsSep " " cleanArgs;
      };
    };
  };

  flake.modules.darwin.base =
    { lib, pkgs, ... }:
    {
      # nix-darwin has no programs.nh module of its own, so the weekly cleanup is
      # a launchd agent here; hjem manages no agents.
      launchd.user.agents.nh-clean.serviceConfig = {
        Label = "org.nixos.nh-clean";

        ProgramArguments = [
          (lib.getExe pkgs.nh)
          "clean"
          "user"
        ]
        ++ cleanArgs;

        StartCalendarInterval = [
          {
            Weekday = 1;
            Hour = 0;
            Minute = 0;
          }
        ];
      };
    };

  flake.modules.hjem.darwin =
    { config, pkgs, ... }:
    {
      packages = [ pkgs.nh ];

      environment.sessionVariables.NH_FLAKE = "${config.directory}/nix-config";
    };
}

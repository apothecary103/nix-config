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
  # The NixOS programs.nh module asserts against nix.gc.automatic also being on.
  flake.modules.nixos.base = {
    nix.gc.automatic = false;

    programs.nh = {
      enable = true;
      flake = "/home/${username}/nix-config";

      clean = {
        enable = true;
        extraArgs = builtins.concatStringsSep " " cleanArgs;
      };
    };
  };

  # Same overlap on darwin, just without an assertion guarding it.
  flake.modules.darwin.base =
    { lib, pkgs, ... }:
    {
      nix.gc.automatic = false;

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

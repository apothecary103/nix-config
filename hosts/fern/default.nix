{
  inputs,
  lib,
  username,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/base
    ../../modules/darwin
    inputs.home-manager.darwinModules.home-manager
  ];

  nixpkgs.overlays = [
    inputs.emacs-overlay.overlays.default

    # pass-import → secretstorage → jeepney. jeepney's checkPhase spawns a
    # D-Bus session via `dbus-run-session`, which fails inside the darwin
    # build sandbox because launchd's DBUS_LAUNCHD_SESSION_BUS_SOCKET is
    # unavailable there. Disable jeepney's test phases on darwin so the
    # extension (and thus `pass import bitwarden ...`) builds on macOS.
    # secretstorage already sets doCheck=false, so only jeepney needs this.
    #
    # NOTE: we override the python3Packages *scope* (overrideScope), not
    # `python3` — nixpkgs binds `python3Packages` to `python313.pkgs`, so an
    # override on `python3` wouldn't reach pass-import's dependencies.
    (
      final: prev:
      lib.optionalAttrs prev.stdenv.isDarwin {
        python3Packages = prev.python3Packages.overrideScope (
          _pyFinal: pyPrev: {
            jeepney = pyPrev.jeepney.overridePythonAttrs (_: {
              doCheck = false;
              doInstallCheck = false;
              # jeepney's importsCheck imports jeepney.io.trio, which pulls in
              # `outcome`/`trio` — those are nativeCheckInputs (test-only), not
              # runtime deps, so they're absent during the import smoke-test
              # and the build breaks. Drop the import check on darwin.
              pythonImportsCheck = [ ];
            });
          }
        );
      }
    )
  ];

  nix.settings = {
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };

  networking.hostName = "fern";

  programs.fish.enable = true;

  environment.shells = with pkgs; [
    fish
  ];

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    description = username;
    shell = pkgs.fish;
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs username;
      hostname = "fern";
    };

    users.${username} = {
      imports = [
        ../../home/base
        ../../home/darwin
      ];
    };
  };

  # home-manager.backupFileExtension = "backup";

  system.stateVersion = 6;
}

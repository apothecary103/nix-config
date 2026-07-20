let
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
  jeepneyOverlay = final: prev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      python3Packages = prev.python3Packages.overrideScope (
        _pyFinal: pyPrev: {
          jeepney = pyPrev.jeepney.overridePythonAttrs (_: {
            doCheck = false;
            doInstallCheck = false;
            # jeepney's importsCheck imports jeepney.io.trio, which pulls in
            # `outcome`/`trio` — those are nativeCheckInputs (test-only), not
            # runtime deps, so they're absent during the import smoke-test
            # and the build breaks. Drop the import check on darwin.
            pythonImportsCheck = [];
          });
        }
      );
    };
in {
  flake.modules.nixos.base.nixpkgs.overlays = [jeepneyOverlay];
  flake.modules.darwin.base.nixpkgs.overlays = [jeepneyOverlay];

  flake.modules.homeManager.base = {
    pkgs,
    config,
    lib,
    ...
  }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      pinentry.package =
        if pkgs.stdenv.isDarwin
        then pkgs.pinentry_mac
        else pkgs.pinentry-gnome3;

      defaultCacheTtl = 3600;
      maxCacheTtl = 86400;
      defaultCacheTtlSsh = 1800;
      maxCacheTtlSsh = 86400;

      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };

    programs.password-store = {
      enable = true;
      package = pkgs.pass.withExtensions (exts: [
        exts.pass-otp
        exts.pass-import
        exts.pass-update
        exts.pass-audit # Checks entries against the HaveIBeenPwned API
      ]);

      settings = {
        PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
        PASSWORD_STORE_CLIP_TIME = "45";
        PASSWORD_STORE_UMASK = "077";
        PASSWORD_STORE_KEY = "mail@apothecary.moe"; # Must match your GPG key ID/email
      };
    };

    # Wires up the native messaging host, but you still must install the
    # "Browserpass" add-on inside your browser for this to actually work.
    programs.browserpass = {
      enable = true;
      browsers = ["librewolf"]; # Defaults to all supported browsers if omitted
    };

    # Exposes pass to the Freedesktop Secret Service API.
    # WARNING: Causes a build-time error if gnome-keyring is also enabled.
    services.pass-secret-service = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
    };
  };
}

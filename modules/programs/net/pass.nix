{
  flake.modules.homeManager.base =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        pinentry.package = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;

        defaultCacheTtl = 600;
        maxCacheTtl = 7200;
        defaultCacheTtlSsh = 600;
        maxCacheTtlSsh = 7200;
      };

      programs.password-store = {
        enable = true;
        package = pkgs.pass.withExtensions (exts: [
          exts.pass-otp
          exts.pass-update
          exts.pass-audit
        ]);

        settings = {
          PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
          PASSWORD_STORE_CLIP_TIME = "45";
          PASSWORD_STORE_UMASK = "077";
          PASSWORD_STORE_KEY = "mail@apothecary.moe";
        };
      };

      # The native messaging host only; the Browserpass add-on still has to be
      # installed in the browser by hand.
      programs.browserpass = {
        enable = true;
        browsers = [ "librewolf" ];
      };

      # Helium (a Chromium fork) isn't in programs.browserpass's supported list,
      # so register its native messaging host by hand. The chromium manifest
      # browserpass ships already whitelists the extension IDs.
      home.file."Library/Application Support/net.imput.helium/NativeMessagingHosts/com.github.browserpass.native.json" =
        lib.mkIf pkgs.stdenv.isDarwin {
          source = "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";
        };

      # Conflicts at build time with gnome-keyring, disabled below.
      services.pass-secret-service = lib.mkIf pkgs.stdenv.isLinux {
        enable = true;
      };
    };

  # niri-flake turns gnome-keyring on unconditionally, leaving two daemons
  # racing to claim org.freedesktop.secrets. The keyring loses nothing by going:
  # its PAM auto-unlock hooks security.pam.services.login, which greetd bypasses.
  flake.modules.nixos.base =
    { lib, ... }:
    {
      services.gnome.gnome-keyring.enable = lib.mkForce false;
    };
}

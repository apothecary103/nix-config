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
          # pass-import removed, taking the jeepney D-Bus dependency with it
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
        browsers = [ "librewolf" ]; # Defaults to all supported browsers if omitted
      };

      # Helium (a Chromium fork, installed as a Homebrew cask on darwin) isn't
      # in programs.browserpass's supported-browser list, so register its native
      # messaging host by hand. The chromium host manifest browserpass ships
      # already whitelists the Browserpass extension IDs; Helium loads it from
      # its app-support NativeMessagingHosts dir (bundle id net.imput.helium).
      # You still have to install the Browserpass extension from the Chrome Web
      # Store for this to work.
      home.file."Library/Application Support/net.imput.helium/NativeMessagingHosts/com.github.browserpass.native.json" =
        lib.mkIf pkgs.stdenv.isDarwin {
          source = "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";
        };

      # Exposes pass to the Freedesktop Secret Service API.
      # WARNING: Causes a build-time error if gnome-keyring is also enabled.
      services.pass-secret-service = lib.mkIf pkgs.stdenv.isLinux {
        enable = true;
      };
    };
}

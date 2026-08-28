{
  flake.modules.hjem.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      gpgSettings = {
        personal-cipher-preferences = "AES256 AES192 AES";
        personal-digest-preferences = "SHA512 SHA384 SHA256";
        personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
        default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
        cert-digest-algo = "SHA512";
        s2k-digest-algo = "SHA512";
        s2k-cipher-algo = "AES256";
        display-charset = "utf-8";
        no-comments = true;
        no-emit-version = true;
        keyid-format = "0xlong";
        list-options = "show-uid-validity";
        verify-options = "show-uid-validity";
        with-fingerprint = true;
        require-cross-certification = true;
        no-symkey-cache = true;
      };

      pinentry = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;
    in
    {
      packages = [
        pkgs.gnupg
        (pkgs.pass.withExtensions (exts: [
          exts.pass-otp
          exts.pass-update
          exts.pass-audit
        ]))
      ];

      environment.sessionVariables = {
        GNUPGHOME = "${config.directory}/.gnupg";
        PASSWORD_STORE_DIR = "${config.directory}/.password-store";
        PASSWORD_STORE_CLIP_TIME = "45";
        PASSWORD_STORE_UMASK = "077";
        PASSWORD_STORE_KEY = "mail@apothecary.moe";
      };

      files = {
        # gpg refuses to read a homedir it does not own outright.
        ".gnupg" = {
          type = "directory";
          permissions = "700";
        };

        ".gnupg/gpg.conf".text = lib.generators.toKeyValue {
          mkKeyValue =
            key: value: if lib.isString value then "${key} ${value}" else lib.optionalString value key;
        } gpgSettings;

        # No unit or agent supervises gpg-agent: nothing here wants an SSH
        # socket up front, so gpg spawns it on demand off this file.
        ".gnupg/gpg-agent.conf".text = ''
          default-cache-ttl 600
          max-cache-ttl 7200
          default-cache-ttl-ssh 600
          max-cache-ttl-ssh 7200
          pinentry-program ${lib.getExe pinentry}
        '';
      };
    };

  # Native messaging hosts for the Browserpass add-on that LibreWolf and Helium
  # install through enterprise policy.
  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      files.".librewolf/native-messaging-hosts/com.github.browserpass.native.json".source =
        "${pkgs.browserpass}/lib/browserpass/hosts/firefox/com.github.browserpass.native.json";

      # Conflicts at build time with gnome-keyring, disabled below.
      systemd.services.pass-secret-service = {
        description = "Pass libsecret service";
        partOf = [ "default.target" ];
        wantedBy = [ "default.target" ];

        serviceConfig = {
          Type = "dbus";
          BusName = "org.freedesktop.secrets";
          ExecStart = "${pkgs.pass-secret-service}/bin/pass_secret_service";
        };
      };

      xdg.data.files."dbus-1/services/org.freedesktop.secrets.service".source =
        "${pkgs.pass-secret-service}/share/dbus-1/services/org.freedesktop.secrets.service";
    };

  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      files = {
        "Library/Application Support/LibreWolf/NativeMessagingHosts/com.github.browserpass.native.json".source =
          "${pkgs.browserpass}/lib/browserpass/hosts/firefox/com.github.browserpass.native.json";

        # Helium (a Chromium fork) needs the chromium manifest instead; the one
        # browserpass ships already whitelists the extension IDs.
        "Library/Application Support/net.imput.helium/NativeMessagingHosts/com.github.browserpass.native.json".source =
          "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";
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

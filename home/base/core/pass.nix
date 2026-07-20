{
  pkgs,
  config,
  lib,
  ...
}:

{
  # ────────────────────────────────────────────────────────────────────────
  # GnuPG — pass encrypts each entry with your GPG key, so a working
  # gpg + gpg-agent with a platform-appropriate pinentry is required.
  # ────────────────────────────────────────────────────────────────────────
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;

    # Native macOS prompt on darwin; Qt pinentry on Linux/Wayland
    # (Hyprland/Niri). Swap for pkgs.pinentry-rofi / pinentry-gnome3 etc.
    # home-manager resolves `pinentry.program` from meta.mainProgram.
    pinentry.package = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;

    # Cache passphrases so you aren't prompted on every `pass` invocation.
    defaultCacheTtl = 3600;
    maxCacheTtl = 86400;
    defaultCacheTtlSsh = 1800;
    maxCacheTtlSsh = 86400;

    # Export GPG_TTY in every shell so tty/curses pinentry fallbacks work.
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };

  # ────────────────────────────────────────────────────────────────────────
  # pass — the standard unix password manager.
  # ────────────────────────────────────────────────────────────────────────
  programs.password-store = {
    enable = true;
    package = pkgs.pass.withExtensions (exts: [
      exts.pass-otp # TOTP/HOTP — replaces Bitwarden's built-in authenticator
      exts.pass-import # `pass import bitwarden export.json` for migration
      exts.pass-update # `pass update <entry>` for easy rotation
      exts.pass-audit # `pass audit` checks entries against HaveIBeenPwned
    ]);

    settings = {
      PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
      PASSWORD_STORE_CLIP_TIME = "45";
      PASSWORD_STORE_UMASK = "077";
      # Set this to your key id/email after you generate/import a GPG key:
      PASSWORD_STORE_KEY = "mail@apothecary.moe";
    };
  };

  # ────────────────────────────────────────────────────────────────────────
  # Browser autofill — closest equivalent to the Bitwarden browser
  # extension. Install the "Browserpass" add-on in Firefox/LibreWolf/etc.
  # and this wires up the native messaging host for it.
  # ────────────────────────────────────────────────────────────────────────
  programs.browserpass = {
    enable = true;
    browsers = [ "librewolf" ]; # defaults to all supported
  };

  # ────────────────────────────────────────────────────────────────────────
  # Secret Service (libsecret) D-Bus bridge — Linux only. Exposes pass to
  # apps speaking the Freedesktop Secret Service API (Evolution, Epiphany,
  # some Electron apps, ...). Conflicts with gnome-keyring (build-time error).
  # ────────────────────────────────────────────────────────────────────────
  services.pass-secret-service = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
  };
}

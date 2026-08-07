{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    let
      parfaitTheme = pkgs.fetchFromGitHub {
        owner = "reizumii";
        repo = "parfait";
        rev = "c95973a2aee0be7f1a895665baa2fb64a3758404";
        hash = "sha256-QUo1Zz6Jp9k+4nriCHHUHC8Imu4BSWTj/i+bf1xon9Y=";
      };

      chromePath =
        if pkgs.stdenv.isDarwin then
          "Library/Application Support/LibreWolf/Profiles/default/chrome"
        else
          ".librewolf/default/chrome";
    in
    {
      programs.librewolf = {
        enable = true;

        policies = {
          SearchEngines = {
            Default = "Startpage";
            PreventInstalls = true;
          };

          ExtensionSettings = {
            "browserpass@maximbaz.com" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/browserpass-ce/latest.xpi";
              installation_mode = "force_installed";
            };

            "tridactyl.vim@cmcaine.co.uk" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/tridactyl-vim/latest.xpi";
              installation_mode = "force_installed";
            };
          };

          Cookies = {
            Allow = [
              "https://github.com"
              "https://codeberg.org"
              "https://reddit.com"
              "https://youtube.com"
              "https://pinterest.com"
              "https://social.treehouse.systems"
              "https://myanimelist.net"
              "https://claude.ai"
              "https://gemini.google.com"
              "https://fluxer.app"
              "https://web.telegram.org"
            ];
          };
        };

        profiles.default = {
          isDefault = true;
          extensions.force = true;

          bookmarks = {
            force = true;
            settings = [
              {
                name = "NixOS Packages";
                url = "https://search.nixos.org";
              }
              {
                name = "Proton Mail";
                url = "https://mail.proton.me/u/0/inbox";
              }
              {
                name = "Codeberg";
                url = "https://codeberg.org";
              }
            ];
          };

          settings = {
            # Allows LibreWolf to read the userChrome.css file
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            # Allows the Parfait theme to render SVGs correctly in dark mode
            "svg.context-properties.content.enabled" = true;

            # RFP breaks canvas-heavy sites, forces GMT and pushes sites to a
            # light theme. Replaced by fingerprintingProtection below.
            "privacy.resistFingerprinting" = false;

            "privacy.fingerprintingProtection" = true;

            # Mode 3 is strict DoH. Mode 2's fallback drops to the system
            # resolver, itself DoT to Quad9 (system/dns.nix), so it buys nothing
            # but a plaintext path when resolved is down.
            "network.trr.mode" = 3;
            "network.trr.uri" = "https://dns.quad9.net/dns-query";

            # The whole ~/.librewolf profile is persisted across the root wipe,
            # so a disk cache would outlive every other trace of a session.
            "browser.cache.disk.enable" = false;

            "dom.security.https_only_mode" = true;
            "network.dns.disablePrefetch" = true;
            "network.predictor.enabled" = false;
            "network.http.speculativeParallelLimit" = 0;
            "beacon.enabled" = false;

            "parfait.blur.enabled" = true;
            "parfait.transparency.enabled" = false;
          };
        };
      };

      home.file."${chromePath}" = {
        source = parfaitTheme;
        recursive = true;
      };
    };
}

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

            # Disable Resist Fingerprinting (RFP). It can break some websites,
            # particularly those that rely on canvas. It also forces GMT as the
            # timezone and often causes websites to prefer a light theme.
            "privacy.resistFingerprinting" = false;

            # Substitute RFP with Firefox's newer, user-friendly protection.
            "privacy.fingerprintingProtection" = true;

            # Use DNS-over-HTTPS (DoH) with Quad9. Mode 2 tries DoH first and
            # falls back to the system DNS if DoH is unavailable. (Mode 3 is
            # strict DoH only.)
            "network.trr.mode" = 2;
            "network.trr.uri" = "https://dns.quad9.net/dns-query";

            "parfait.blur.enabled" = true;
          };
        };
      };

      # This symlinks the fetched repository into LibreWolf profile's chrome directory.
      home.file."${chromePath}" = {
        source = parfaitTheme;
        recursive = true;
      };
    };
}

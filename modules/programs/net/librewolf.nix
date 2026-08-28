{
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    let
      parfaitTheme = pkgs.fetchFromGitHub {
        owner = "reizumii";
        repo = "parfait";
        rev = "c95973a2aee0be7f1a895665baa2fb64a3758404";
        hash = "sha256-QUo1Zz6Jp9k+4nriCHHUHC8Imu4BSWTj/i+bf1xon9Y=";
      };

      inherit (pkgs.stdenv) isDarwin;

      configPath = if isDarwin then "Library/Application Support/LibreWolf" else ".librewolf";
      profilePath = if isDarwin then "${configPath}/Profiles/default" else "${configPath}/default";

      package = pkgs.librewolf.override (old: {
        extraPolicies = (old.extraPolicies or { }) // {
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

          ManagedBookmarks = [
            { toplevel_name = "Nix configuration"; }
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
      });

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
    in
    {
      packages = [ package ];

      files = {
        "${configPath}/profiles.ini".text = lib.generators.toINI { } {
          General = {
            StartWithLastProfile = 1;
          }
          // lib.optionalAttrs (!isDarwin) { Version = 2; };

          Profile0 = {
            Name = "default";
            Path = if isDarwin then "Profiles/default" else "default";
            IsRelative = 1;
            Default = 1;
          };
        };

        "${profilePath}/user.js".text = lib.concatLines (
          lib.mapAttrsToList (name: value: ''user_pref("${name}", ${builtins.toJSON value});'') settings
        );

        "${profilePath}/chrome".source = parfaitTheme;
      };
    };
}

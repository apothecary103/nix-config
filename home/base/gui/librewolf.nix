{ pkgs, ... }:

let
  parfaitTheme = pkgs.fetchFromGitHub {
    owner = "reizumii";
    repo = "parfait";
    rev = "master";
    hash = "sha256-Fs3iV8RO/jwfSc6q/rwM/xcwNfy/iua+MsuGgM5M8mM=";
  };
in
{
  programs.librewolf = {
    enable = true;

    policies = {
      Cookies = {
        Allow = [
          "https://github.com"
          "https://codeberg.org"
          "https://reddit.com"
          "https://youtube.com"
          "https://pinterest.com"
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

      SearchEngines = {
       	Default = "Startpage";
       	PreventInstalls = true;
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
      };
    };
  };

  # This symlinks the fetched repository into LibreWolf profile's chrome directory.
  # Note: 'default' here corresponds to the profile name.
  home.file.".librewolf/default/chrome" = {
    source = parfaitTheme;
    recursive = true;
  };
}

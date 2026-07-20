{ pkgs, ... }:

let
  parfaitTheme = pkgs.fetchFromGitHub {
    owner = "reizumii";
    repo = "parfait";
    rev = "master";
    hash = "sha256-C2zCAmY1cjDYLJctMu0yOfIhl1ZoO0ONYdy29jPDBSM=";
  };
in
{
  programs.librewolf = {
    enable = false;

    policies = {
      Cookies = {
        Allow = [
          "https://github.com"
          "https://reddit.com"
          "https://youtube.com"
          "https://pinterest.com"
        ];
      };
    };

    profiles.default = {
      isDefault = true;

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
        ];
      };

      settings = {
        # Allows LibreWolf to read the userChrome.css file
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        # Allows the Parfait theme to render SVGs correctly in dark mode
        "svg.context-properties.content.enabled" = true; 
      };
    };
  };

  # 5. Declaratively install the Parfait theme
  # This symlinks the entire fetched repository into your LibreWolf profile's chrome directory.
  # Note: If you name your profile something other than 'default', change the path below!
  home.file.".librewolf/default/chrome" = {
    source = parfaitTheme;
    recursive = true;
  };
}

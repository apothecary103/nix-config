{
  inputs,
  username,
  ...
}:
let
  bundleId = "net.imput.helium";

  policies = {
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    BlockThirdPartyCookies = true;
    # Keep cookies across restarts, and clear nothing on exit.
    DefaultCookiesSetting = 1;
    ClearBrowsingDataOnExitList = [ ];
    BrowserSignin = 0;
    HttpsOnlyMode = "force_enabled";
    MetricsReportingEnabled = false;
    NetworkPredictionOptions = 2;
    PasswordManagerEnabled = false;
    PrivacySandboxAdMeasurementEnabled = false;
    PrivacySandboxAdTopicsEnabled = false;
    PrivacySandboxSiteEnabledAdsEnabled = false;
    SearchSuggestEnabled = false;
    SyncDisabled = true;
    UrlKeyedAnonymizedDataCollectionEnabled = false;

    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "Startpage";
    DefaultSearchProviderKeyword = "startpage.com";
    DefaultSearchProviderSearchURL = "https://www.startpage.com/sp/search?query={searchTerms}&cat=web&pl=chrome";

    ExtensionInstallForcelist = [
      "naepdomgkenhinolocfifgehidddafch;https://clients2.google.com/service/update2/crx"
    ];
  };
in
{
  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = [ inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.helium ];
    };

  # On Wayland (NIXOS_OZONE_WL), with colour management so pages and video
  # tagged wider than sRGB reach river's Display P3 instead of being clipped.
  # Chromium keeps only the last --enable-features, so this repeats the
  # window decorations the wrapper already asks for. Cookies stay encrypted
  # with the fixed key they were written with: a keyring turning up in one
  # session and not the next would otherwise lock them out.
  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      packages = [
        (inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.helium.override {
          commandLineArgs = "--password-store=basic --enable-features=WaylandWindowDecorations,WaylandWpColorManagerV1";
        })
      ];
    };

  # Helium on Linux reads Chromium's policy directory.
  flake.modules.nixos.base.environment.etc."chromium/policies/managed/helium.json".text =
    builtins.toJSON policies;

  flake.modules.darwin.base =
    { lib, pkgs, ... }:
    let
      plist = pkgs.writeText "${bundleId}.plist" (lib.generators.toPlist { escape = true; } policies);
      target = "/Library/Managed Preferences/${username}/${bundleId}.plist";
    in
    {
      system.activationScripts.postActivation.text = ''
        install -d -m 0755 "$(dirname "${target}")"
        install -m 0644 ${plist} "${target}"
        /usr/bin/killall -u ${username} cfprefsd 2>/dev/null || true
      '';
    };
}

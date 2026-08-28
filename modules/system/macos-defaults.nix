{ username, ... }:
{
  flake.modules.darwin.base = { config, ... }: {
    security.pam.services.sudo_local.touchIdAuth = true;

    system.keyboard = {
      enableKeyMapping = true;

      # Map Caps Lock (HID 0x39) to Backspace/Delete (HID 0x2A)
      # Base macOS keyboard HID value is 0x700000000 (30064771072 in decimal)
      userKeyMapping = [
        {
          HIDKeyboardModifierMappingSrc = 30064771129;
          HIDKeyboardModifierMappingDst = 30064771114;
        }
      ];
    };

    system.defaults = {
      menuExtraClock.Show24Hour = true;
      smb.NetBIOSName = config.networking.hostName;

      ActivityMonitor = {
        SortColumn = "CPUUsage";
        SortDirection = 0;
      };

      NSGlobalDomain = {
        AppleKeyboardUIMode = 3;
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 10;
        KeyRepeat = 2;

        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;

        _HIHideMenuBar = false;
        NSWindowResizeTime = 0.001;

        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
      };

      dock = {
        autohide = true;

        autohide-delay = 0.0;
        autohide-time-modifier = 0.0;
        expose-animation-duration = 0.1;
        mineffect = "scale";
        launchanim = false;

        mru-spaces = false;
        orientation = "bottom";
        show-process-indicators = true;
        show-recents = false;
        showhidden = true;
        tilesize = 64;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "clmv";
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };

      # Preferences nix-darwin has no dedicated options for
      CustomSystemPreferences = {
        NSGlobalDomain = {
          AppleAccentColor = 6;
          AppleScrollerPagingBehavior = true;
          AppleWindowTabbingMode = "always";
          QLPanelAnimationDuration = 0;
        };

        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
          allowIdentifierForAdvertising = false;
          forceLimitAdTracking = true;
        };

        "com.apple.CrashReporter" = {
          DialogType = "none";
        };

        "com.apple.Siri" = {
          StatusMenuVisible = false;
          UserHasDeclinedEnable = true;
        };

        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };

        "com.apple.finder" = {
          NewWindowTarget = "PfHm";
          NewWindowTargetPath = "file://${config.users.users.${username}.home}/";
          QLEnableTextSelection = true;
          ShowExternalHardDrivesOnDesktop = false;
          ShowHardDrivesOnDesktop = false;
          ShowMountedServersOnDesktop = false;
          ShowRemovableMediaOnDesktop = false;
          _FXSortFoldersFirst = true;
        };

        "com.apple.Safari" = {
          AutoOpenSafeDownloads = false;
          IncludeDevelopMenu = true;
          IncludeInternalDebugMenu = true;
          SendDoNotTrackHTTPHeader = true;
          SuppressSearchSuggestions = true;
          UniversalSearchEnabled = false;
          WebKitDeveloperExtras = true;
          WebKitDeveloperExtrasEnabledPreferenceKey = true;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
        };

        "com.apple.screencapture" = {
          name = "screenshot";
          include-date = false;
          disable-shadow = true;
        };
      };
    };
  };
}

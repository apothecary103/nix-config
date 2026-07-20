{
  # Force Electron/Chromium and Firefox onto their native Wayland backends.
  #
  # By default these apps run under XWayland, which has no HiDPI awareness: they
  # render at 1x and the compositor upscales the result to the 2x Retina panel,
  # so their text looks soft/blurry next to native Wayland apps (which render at
  # full 2x and match macOS). Switching them to Wayland makes them draw at native
  # scale, fixing the typography. Fontconfig is handled separately.
  flake.modules.nixos.base.environment.sessionVariables = {
    # Chromium/Electron Ozone backend — Signal, Vesktop, and any Electron app.
    NIXOS_OZONE_WL = "1";

    # Firefox-based browsers — LibreWolf and Zen.
    MOZ_ENABLE_WAYLAND = "1";
  };
}

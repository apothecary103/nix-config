{
  # Under XWayland these apps render at 1x and the compositor upscales to the 2x
  # Retina panel, so their text comes out soft next to native Wayland apps.
  flake.modules.nixos.base.environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";

    MOZ_ENABLE_WAYLAND = "1";
  };
}

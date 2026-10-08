{
  # Under XWayland Electron apps render at 1x and the compositor upscales to the
  # 2x Retina panel, so their text comes out soft next to native Wayland apps.
  # Firefox needs nothing here: nixpkgs' wrapper already defaults it to Wayland.
  flake.modules.nixos.base.environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

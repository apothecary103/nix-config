{
  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = [ pkgs.prismlauncher ];
    };

  # Minecraft 26.3 opens its window through SDL3, which falls back to XWayland
  # on river for want of fifo-v1. There OpenGL fails outright (so the game
  # drops to Vulkan without being asked) and it renders at half the panel's
  # resolution. Native Wayland gives both APIs, at full resolution. The
  # instance itself is set to prefer Vulkan, with Vitrail for shader packs.
  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      packages = [
        (pkgs.symlinkJoin {
          inherit (pkgs.prismlauncher) name meta;
          paths = [ pkgs.prismlauncher ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/prismlauncher --set SDL_VIDEO_DRIVER wayland
          '';
        })
      ];
    };
}

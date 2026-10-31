{
  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = [ pkgs.prismlauncher ];
    };

  # Minecraft 26.3 opens its window through SDL3, which falls back to XWayland
  # on river for want of fifo-v1. There OpenGL fails outright (so the game
  # drops to Vulkan without being asked) and it renders at half the panel's
  # resolution. Native Wayland gives both APIs; SDL then still sizes the
  # window in logical pixels (1512x982 at scale 2) unless told to scale it
  # 1:1 to the panel, since the game does not ask for high pixel density. The
  # instance itself is set to prefer Vulkan, with Vitrail for shader packs.
  flake.modules.hjem.linux =
    { pkgs, palette, ... }:
    let
      s = palette.surface;
    in
    {
      packages = [
        (pkgs.symlinkJoin {
          inherit (pkgs.prismlauncher) name meta;
          paths = [ pkgs.prismlauncher ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/prismlauncher \
              --set SDL_VIDEO_DRIVER wayland \
              --set SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY 1
          '';
        })
      ];

      # Prism's own theme in the system palette (as qt.nix lays it out), with a
      # stylesheet putting the whole launcher in azuki; Prism has no font
      # setting beyond its console. Selected as "orchard" in prismlauncher.cfg.
      xdg.data.files = {
        "PrismLauncher/themes/orchard/theme.json".text = builtins.toJSON {
          name = "Orchard";
          widgets = "Fusion";
          qssFilePath = "themeStyle.css";
          colors = {
            Window = s.panel;
            WindowText = s.text;
            Base = s.background;
            AlternateBase = s.neutral0;
            ToolTipBase = s.background;
            ToolTipText = s.text;
            Text = s.text;
            Button = s.panel;
            ButtonText = s.text;
            BrightText = palette.status.error;
            ErrorHighlight = palette.status.error;
            Link = palette.hue.snow;
            Highlight = palette.hue.snow;
            HighlightedText = s.background;
            fadeColor = s.neutral2;
            fadeAmount = 0.5;
          };
          logColors = {
            Launcher = palette.hue.snow;
            Info = s.text;
            Debug = s.neutral4;
            Warning = palette.status.warning;
            Error = palette.status.error;
            FatalError = palette.status.error;
          };
        };
        "PrismLauncher/themes/orchard/themeStyle.css".text = ''
          * {
            font-family: "azuki_font";
            font-size: 11pt;
          }
        '';
      };
    };
}

{ inputs, ... }: {
  flake.modules.darwin.base = { pkgs, ... }: {
    services.yabai = {
      enable = true;

      # AhsanFazal's fork shares upstream's makefile, so nixpkgs' build and
      # postPatch apply unchanged. Its binary still reports the base version,
      # hence dropping the version-check hook.
      package = pkgs.yabai.overrideAttrs (_: {
        src = inputs.yabai-src;
        version = "7.1.25-unstable-${inputs.yabai-src.shortRev}";
        doInstallCheck = false;
      });

      config = {
        layout = "bsp";
        top_padding = 10;
        bottom_padding = 10;
        left_padding = 10;
        right_padding = 10;
        window_gap = 10;

        mouse_follows_focus = "on";
        focus_follows_mouse = "autoraise";
        window_placement = "second_child";
      };

      extraConfig = ''
        yabai -m rule --add app="^System Settings$" manage=off
        yabai -m rule --add app="^Calculator$" manage=off
      '';
    };

    services.skhd = {
      enable = true;
      skhdConfig = ''
        alt - t: open -n -a Ghostty

        alt - 1 : yabai -m space --focus 1
        alt - 2 : yabai -m space --focus 2
        alt - 3 : yabai -m space --focus 3
        alt - 4 : yabai -m space --focus 4
        alt - 5 : yabai -m space --focus 5
        alt - 6 : yabai -m space --focus 6
        alt - 7 : yabai -m space --focus 7
        alt - 8 : yabai -m space --focus 8
        alt - 9 : yabai -m space --focus 9

        shift + alt - 1 : yabai -m window --space 1
        shift + alt - 2 : yabai -m window --space 2
        shift + alt - 3 : yabai -m window --space 3
        shift + alt - 4 : yabai -m window --space 4
        shift + alt - 5 : yabai -m window --space 5
        shift + alt - 6 : yabai -m window --space 6
        shift + alt - 7 : yabai -m window --space 7
        shift + alt - 8 : yabai -m window --space 8
        shift + alt - 9 : yabai -m window --space 9

        alt - v : yabai -m window --toggle float --grid 4:4:1:1:2:2

        shift + alt - r : launchctl kickstart -k "gui/''${UID}/org.nixos.yabai"
      '';
    };
  };
}

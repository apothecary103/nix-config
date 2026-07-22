{ inputs, ... }: {
  flake.modules.darwin.base = { pkgs, ... }: {
    services.yabai = {
      enable = true;
      enableScriptingAddition = true;

      # AhsanFazal's fork built from source; it shares upstream's makefile, so
      # nixpkgs' build/postPatch apply unchanged. The binary still reports the
      # base version, so the version-check hook is dropped to avoid a mismatch.
      package = pkgs.yabai.overrideAttrs (old: {
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
        # Open Ghostty terminal: Alt + T
        alt - t: open -n -a Ghostty

        # Focus spaces 1 through 9 using Alt + Number
        alt - 1 : yabai -m space --focus 1
        alt - 2 : yabai -m space --focus 2
        alt - 3 : yabai -m space --focus 3
        alt - 4 : yabai -m space --focus 4
        alt - 5 : yabai -m space --focus 5
        alt - 6 : yabai -m space --focus 6
        alt - 7 : yabai -m space --focus 7
        alt - 8 : yabai -m space --focus 8
        alt - 9 : yabai -m space --focus 9

        # Send focused window to space 1-9 (Shift + Alt + Number)
        shift + alt - 1 : yabai -m window --space 1
        shift + alt - 2 : yabai -m window --space 2
        shift + alt - 3 : yabai -m window --space 3
        shift + alt - 4 : yabai -m window --space 4
        shift + alt - 5 : yabai -m window --space 5
        shift + alt - 6 : yabai -m window --space 6
        shift + alt - 7 : yabai -m window --space 7
        shift + alt - 8 : yabai -m window --space 8
        shift + alt - 9 : yabai -m window --space 9

        # Focus windows: Alt + h/j/k/l
        alt - h : yabai -m window --focus west
        alt - j : yabai -m window --focus south
        alt - k : yabai -m window --focus north
        alt - l : yabai -m window --focus east

        # Swap windows: Shift + Alt + h/j/k/l
        shift + alt - h : yabai -m window --swap west
        shift + alt - j : yabai -m window --swap south
        shift + alt - k : yabai -m window --swap north
        shift + alt - l : yabai -m window --swap east

        # Toggle float: Alt + f
        alt - f : yabai -m window --toggle float --grid 4:4:1:1:2:2

        # Restart yabai: Shift + Alt + r
        shift + alt - r : launchctl kickstart -k "gui/''${UID}/org.nixos.yabai"
      '';
    };
  };
}

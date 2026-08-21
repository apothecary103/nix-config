# hyprlock and hypridle are plain ext-session-lock-v1 / ext-idle-notify-v1
# clients, so neither needs Hyprland. niri binds `loginctl lock-session` rather
# than hyprlock directly, so the keybind, the idle timer and the
# resume-from-suspend path all go through logind.
{
  flake.modules.nixos.base = {
    security.pam.services.hyprlock = { };
  };

  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      loginctl = lib.getExe' pkgs.systemd "loginctl";
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      pidof = lib.getExe' pkgs.procps "pidof";
      gpgConnectAgent = lib.getExe' pkgs.gnupg "gpg-connect-agent";
      hyprlock = lib.getExe pkgs.hyprlock;

      rgb = colour: "rgb(${lib.removePrefix "#" colour})";
    in
    {
      # Orchard covers no lock screen — a layout is too much taste to inherit —
      # so this one is written by hand against the palette.
      rum.programs.hyprlock = {
        enable = true;

        settings = {
          general = {
            grace = 0;
            hide_cursor = true;
            ignore_empty_input = true;
          };

          background = [
            {
              color = rgb palette.base;
              blur_passes = 0;
            }
          ];

          label = [
            {
              text = "$TIME";
              color = rgb palette.text;
              font_size = 92;
              font_family = "Maple Mono NF CN";
              position = "0, 128";
              halign = "center";
              valign = "center";
            }
            {
              text = ''cmd[update:60000] date +"%A, %-d %B"'';
              color = rgb palette.subtext0;
              font_size = 20;
              font_family = "Adwaita Sans";
              position = "0, 56";
              halign = "center";
              valign = "center";
            }
          ];

          input-field = [
            {
              size = "280, 52";
              position = "0, -96";
              halign = "center";
              valign = "center";

              outline_thickness = 2;
              rounding = 12;

              outer_color = rgb palette.surface1;
              inner_color = rgb palette.mantle;
              font_color = rgb palette.text;
              check_color = rgb palette.warning;
              fail_color = rgb palette.error;
              capslock_color = rgb palette.accent;

              dots_size = 0.28;
              dots_spacing = 0.32;
              dots_center = true;

              fade_on_empty = false;
              placeholder_text = ''<span foreground="##${lib.removePrefix "#" palette.overlay1}">Password</span>'';
              fail_text = "<i>$FAIL ($ATTEMPTS)</i>";

              shadow_passes = 0;
            }
          ];
        };
      };

      rum.programs.hypridle = {
        enable = true;

        settings = {
          general = {
            # Locking flushes the gpg-agent cache, otherwise a locked screen
            # still fronts an agent that will hand out the password store and
            # the SSH key without a prompt.
            lock_cmd = "${pidof} hyprlock || { ${gpgConnectAgent} reloadagent /bye; ${hyprlock}; }";
            before_sleep_cmd = "${loginctl} lock-session";
          };

          listener = [
            {
              timeout = 300;
              on-timeout = "${loginctl} lock-session";
            }
            {
              timeout = 900;
              on-timeout = "${systemctl} suspend";
            }
          ];
        };
      };

      # rum's module only writes the config, so the daemon needs its own unit.
      systemd.services.hypridle = {
        description = "Idle management daemon";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];

        serviceConfig = {
          ExecStart = lib.getExe pkgs.hypridle;
          Restart = "on-failure";
        };
      };
    };
}

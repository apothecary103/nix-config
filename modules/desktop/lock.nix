# hyprlock and hypridle are plain ext-session-lock-v1 / ext-idle-notify-v1
# clients, so the same pair locks both niri and Hyprland. The compositors bind
# `loginctl lock-session` rather than hyprlock directly, so the keybind, the
# idle timer and the resume-from-suspend path all go through logind.
{
  flake.modules.nixos.base = {
    security.pam.services.hyprlock = { };
  };

  flake.modules.hjem.linux =
    { lib, pkgs, ... }:
    let
      loginctl = lib.getExe' pkgs.systemd "loginctl";
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      pidof = lib.getExe' pkgs.procps "pidof";
      gpgConnectAgent = lib.getExe' pkgs.gnupg "gpg-connect-agent";
      hyprlock = lib.getExe pkgs.hyprlock;
    in
    {
      # Colours, background and input-field come from catppuccin's bundled
      # hyprlock.conf (desktop/theme.nix, autoEnable).
      rum.programs.hyprlock = {
        enable = true;

        settings.general = {
          grace = 0;
          hide_cursor = true;
          ignore_empty_input = true;
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

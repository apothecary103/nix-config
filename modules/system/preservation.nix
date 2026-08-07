# frieren wipes the btrfs @ subvolume on every boot (see
# modules/hosts/frieren/impermanence.nix) and /home lives on @, so anything not
# on @nix, @persist or @log is gone unless bind-mounted back from /persist.
# /var/log is its own subvolume, hence absent here.
{ inputs, username, ... }:
{
  flake.modules.nixos.base = {
    imports = [ inputs.preservation.nixosModules.preservation ];

    # `passwd` would not survive a reboot, so the hashes live on the persistent
    # volume, set once at install time with mkpasswd -m yescrypt.
    users.mutableUsers = false;
    users.users.${username}.hashedPasswordFile = "/persist/passwords/${username}";
    users.users.root.hashedPasswordFile = "/persist/passwords/root";

    preservation = {
      enable = true;
      preserveAt."/persist" = {
        directories = [
          # NixOS uid/gid map: needed in initrd so early users resolve.
          {
            directory = "/var/lib/nixos";
            inInitrd = true;
          }
          "/var/lib/systemd/timers"
          "/var/lib/systemd/backlight"
          "/var/lib/systemd/rfkill"
          "/var/lib/bluetooth"
          "/var/lib/upower"
          # iwd is NetworkManager's wifi backend: this holds the PSKs.
          "/var/lib/iwd"
          "/var/lib/NetworkManager"
          "/etc/NetworkManager/system-connections"
          # tuigreet's --remember/--remember-session state lives here.
          {
            directory = "/var/cache/tuigreet";
            user = "greeter";
            group = "greeter";
          }
        ];
        files = [
          {
            file = "/etc/machine-id";
            inInitrd = true;
          }
          {
            file = "/var/lib/systemd/random-seed";
            how = "symlink";
            inInitrd = true;
            configureParent = true;
          }
        ];

        # Only what home-manager does not regenerate: secrets and long-lived
        # app state.
        users.${username} = {
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
            {
              directory = ".gnupg";
              mode = "0700";
            }
            "Documents"
            "Downloads"
            "Pictures"
            "Music"
            "Videos"
            "Projects"
            "nix-config"

            ".password-store"
            ".librewolf"
            ".local/share"
            ".local/state"

            ".claude"
            ".config/gh"
            ".config/Signal"
            ".config/vesktop"

            # The quickshell launcher's frecency store, which orders the app
            # list — without this the ordering resets on every boot.
            ".cache/quickshell"
          ];
          files = [ ".claude.json" ];
        };
      };
    };

    # With a persistent machine-id this commit service has nothing to do and
    # would otherwise fail; see the preservation impermanence example.
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    # Preservation creates the persisted subdirs but not the home root itself,
    # which on a wiped root has to exist with the right ownership before
    # home-manager can lay down its files.
    systemd.tmpfiles.settings.preservation-home."/home/${username}".d = {
      user = username;
      group = "users";
      mode = "0700";
    };

    # Placed by hand at install time, so pin the mode rather than trusting the
    # installer shell's umask.
    systemd.tmpfiles.settings.password-hashes = {
      "/persist/passwords".d = {
        user = "root";
        group = "root";
        mode = "0700";
      };
      "/persist/passwords/*".z = {
        user = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}

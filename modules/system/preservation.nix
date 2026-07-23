# Ephemeral root and home: frieren wipes the btrfs @ subvolume on every boot
# (see modules/hosts/frieren/impermanence.nix), and /home lives on @, so it is
# wiped too. Anything not on a persistent subvolume (@nix, @persist, @log) is
# gone after a reboot unless preservation bind-mounts it back from /persist.
# /var/log is its own subvolume, so it is already persistent and not listed
# here.
{ inputs, username, ... }:
{
  flake.modules.nixos.base = {
    imports = [ inputs.preservation.nixosModules.preservation ];

    # A wiped root means `passwd` would not survive a reboot, so passwords are
    # declarative: the hashes live on the persistent volume and are set once at
    # install time (see the README). mkpasswd -m yescrypt generates them.
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
          "/var/lib/systemd/coredump"
          "/var/lib/systemd/timers"
          "/var/lib/systemd/backlight"
          "/var/lib/systemd/rfkill"
          "/var/lib/bluetooth"
          # iwd is NetworkManager's wifi backend: this holds the PSKs.
          "/var/lib/iwd"
          "/var/lib/NetworkManager"
          "/etc/NetworkManager/system-connections"
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

        # Home is wiped each boot, so keep only what home-manager does not
        # regenerate: secrets and long-lived app state. Anything not listed
        # here disappears on reboot, which is the point. Tune as needed.
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
          ];
        };
      };
    };

    # With a persistent machine-id this commit service has nothing to do and
    # would otherwise fail; see the preservation impermanence example.
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    # Preservation creates the persisted subdirs, but not the home root itself
    # (it used to live on the persistent @home). On the wiped root, create it
    # with the right ownership so the user can write to ~ and home-manager can
    # lay down its files.
    systemd.tmpfiles.settings.preservation-home."/home/${username}".d = {
      user = username;
      group = "users";
      mode = "0700";
    };
  };
}

# The LUKS install of frieren, the alternative to the image (./image.nix). Run
# as root from any NixOS live environment with the ESP and Root partitions in place:
#   frieren-install /path/to/id_ed25519
{
  config,
  lib,
  username,
  ...
}:
let
  frieren = config.flake.nixosConfigurations.frieren-luks.config;
  luksDevice = frieren.disko.devices.disk.root.device;
  espDevice = frieren.fileSystems."/boot".device;
in
{
  perSystem =
    {
      inputs',
      pkgs,
      system,
      ...
    }:
    {
      packages = lib.optionalAttrs (system == "aarch64-linux") {
        frieren-install = pkgs.writeShellApplication {
          name = "frieren-install";
          runtimeInputs = [
            inputs'.disko.packages.disko
            pkgs.cryptsetup
            pkgs.git
            pkgs.jq
            pkgs.nixos-install-tools
            pkgs.openssh
            pkgs.util-linux
          ];
          text = ''
            if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
              echo "usage: frieren-install <frieren id_ed25519>" >&2
              echo "The key in secrets.nix: agenix decrypts with it and it fetches asahi-firmware." >&2
              exit 1
            fi
            if [ "$(id -u)" -ne 0 ]; then
              echo "frieren-install must run as root" >&2
              exit 1
            fi
            key=$(realpath "$1")
            flake=/tmp/nix-config

            export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

            # asahi.sh pins the ESP's FAT serial, and the Root partition the
            # Asahi installer created is the one laid out directly after it.
            udevadm settle
            if [ "$(blkid -t UUID=${lib.removePrefix "/dev/disk/by-uuid/" espDevice} -o device | wc -l)" -ne 1 ]; then
              echo "Expected exactly one ESP with ${espDevice}; remove a leftover one from macOS." >&2
              exit 1
            fi
            esp=$(realpath ${espDevice})
            disk=/dev/$(lsblk -no PKNAME "$esp")
            # install-existing.sh names the partition it creates Frieren;
            # without it, the Root partition follows the ESP.
            root=$(realpath -e /dev/disk/by-partlabel/Frieren 2>/dev/null || true)
            if [ -z "$root" ]; then
              root=$(
                sfdisk -J "$disk" | jq -r --arg esp "$esp" '
                  .partitiontable.partitions
                  | (map(select(.node == $esp))[0] | .start + .size) as $end
                  | map(select(.start >= $end)) | sort_by(.start) | .[0].node // empty
                '
              )
            fi
            if [ -z "$root" ]; then
              echo "No partition follows the ESP $esp: run asahi.sh from macOS first." >&2
              exit 1
            fi
            # blkid -p exits 2 when it finds no signature at all.
            if blkid -p "$root" >/dev/null 2>&1 || [ "$?" -ne 2 ]; then
              echo "$root is not empty; refusing to format it." >&2
              blkid -p "$root" >&2 || true
              exit 1
            fi

            echo "ESP:  $esp (kept as is)"
            echo "Root: $root ($(lsblk -dno SIZE "$root")) -> LUKS + btrfs, ALL DATA LOST"
            read -rp "Type frieren to continue: " confirm
            [ "$confirm" = frieren ] || exit 1

            rm -rf "$flake"
            git clone https://github.com/apothecary103/nix-config "$flake"

            # Formatted with the UUID disko.nix pins, so the config boots
            # unchanged; disko then sees an open LUKS device and only lays down
            # the btrfs subvolumes inside it.
            cryptsetup luksFormat --type luks2 --uuid ${lib.removePrefix "/dev/disk/by-uuid/" luksDevice} "$root"
            cryptsetup open --allow-discards "$root" ${frieren.disko.devices.disk.root.content.name}
            udevadm settle
            disko --mode format,mount --flake "$flake#frieren-luks"
            mkdir -p /mnt/boot
            mount -o fmask=0022,dmask=0022 "$esp" /mnt/boot

            # agenix decrypts during the install's own activation, so the
            # identity has to be in place before nixos-install.
            install -D -m 600 "$key" /mnt/home/${username}/.ssh/id_ed25519
            ssh-keygen -y -f "$key" > /mnt/home/${username}/.ssh/id_ed25519.pub

            nixos-install --flake "$flake#frieren-luks" --no-root-passwd --no-channel-copy

            cp -a "$flake" /mnt/home/${username}/nix-config
            nixos-enter --root /mnt -c 'chown -R ${username}:users /home/${username}'
            echo "Password for ${username}:"
            until nixos-enter --root /mnt -c 'passwd ${username}'; do :; done

            umount -R /mnt
            cryptsetup close ${frieren.disko.devices.disk.root.content.name}
            echo "Done. Reboot."
          '';
        };
        disko = inputs'.disko.packages.disko;
      };
    };
}

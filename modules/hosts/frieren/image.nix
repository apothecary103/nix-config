# The frieren system as an image the Asahi Installer writes into a new
# partition, the same way it writes Fedora's images. The installer creates the
# ESP and the Root partition itself, from free space, and leaves the existing
# partitions alone.
#
# This is nixosConfigurations.frieren, so `nh os switch` on the installed
# machine rebuilds this layout. The LUKS layout in disko.nix is
# nixosConfigurations.frieren-luks, for the live-environment install path
# (frieren-install); an image cannot hold a LUKS passphrase.
#
# Nothing secret is in the image. asahi.sh collects the password, the frieren
# key, Wi-Fi and the repo on macOS and drops them on the new ESP as
# frieren-seed/; frieren-first-boot applies them before the greeter starts and
# deletes them. Anything missing from the seed is asked for on tty1 instead.
{
  config,
  inputs,
  lib,
  username,
  ...
}:
let
  supportedFw = [
    "12.3"
    "12.3.1"
    "13.5"
    "14.8.3"
  ];

  # The ESP is mounted at /boot; asahi.sh writes the seed there.
  seed = "/boot/frieren-seed";
  home = "/home/${username}";
in
{
  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      config.flake.modules.nixos."hosts/frieren"
      (
        { pkgs, ... }:
        {
          disko.enableConfig = false;

          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
            # The installer gives Root the rest of the free space.
            autoResize = true;
          };
          boot.growPartition = true;

          systemd.services.frieren-first-boot = {
            description = "First-boot setup for frieren: password, key, Wi-Fi, repo";
            wantedBy = [ "multi-user.target" ];
            before = [
              "greetd.service"
              "NetworkManager.service"
            ];
            unitConfig = {
              ConditionPathExists = "!/var/lib/frieren-first-boot";
              RequiresMountsFor = [
                "/boot"
                home
              ];
            };
            path = [
              pkgs.coreutils
              pkgs.git
              pkgs.openssh
              pkgs.shadow
              pkgs.util-linux
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              StandardInput = "tty";
              StandardOutput = "tty";
              TTYPath = "/dev/tty1";
              TTYReset = true;
              TTYVHangup = true;
            };
            script = ''
              set -eu
              echo "First boot of frieren."
              install -d -m 700 -o ${username} -g users ${home} ${home}/.ssh

              if [ -s ${seed}/password.hash ]; then
                echo "Setting the password for ${username} from the installer."
                usermod -p "$(cat ${seed}/password.hash)" ${username}
              else
                echo "Set the password for ${username}:"
                until /run/wrappers/bin/passwd ${username}; do
                  echo "Try again."
                done
              fi

              key=$(mktemp)
              if [ -s ${seed}/id_ed25519 ]; then
                echo "Installing the frieren key from the installer."
                cat ${seed}/id_ed25519 >"$key"
              else
                until
                  echo "Paste the frieren id_ed25519 key, press Enter, then Ctrl-D:"
                  cat >"$key"
                  ssh-keygen -y -P "" -f "$key" >/dev/null
                do
                  echo "That is not an unencrypted OpenSSH private key. Try again."
                done
              fi
              install -m 600 -o ${username} -g users "$key" ${home}/.ssh/id_ed25519
              ssh-keygen -y -P "" -f "$key" >${home}/.ssh/id_ed25519.pub
              chown ${username}:users ${home}/.ssh/id_ed25519.pub
              shred -u "$key"

              if [ -s ${seed}/known_hosts ]; then
                cat ${seed}/known_hosts >>${home}/.ssh/known_hosts
                chown ${username}:users ${home}/.ssh/known_hosts
                chmod 644 ${home}/.ssh/known_hosts
              fi

              # NetworkManager only loads root-owned 0600 keyfiles.
              if [ -d ${seed}/system-connections ]; then
                echo "Adding Wi-Fi networks."
                install -d -m 700 /etc/NetworkManager/system-connections
                for c in ${seed}/system-connections/*.nmconnection; do
                  [ -e "$c" ] || continue
                  install -m 600 "$c" /etc/NetworkManager/system-connections/
                done
              fi

              if [ -s ${seed}/nix-config.bundle ] && [ ! -e ${home}/nix-config ]; then
                echo "Cloning nix-config into ${home}/nix-config."
                runuser -u ${username} -- git clone -q ${seed}/nix-config.bundle ${home}/nix-config
                runuser -u ${username} -- git -C ${home}/nix-config remote remove origin
                while read -r kind url; do
                  case "$kind" in
                    fetch) runuser -u ${username} -- git -C ${home}/nix-config remote add origin "$url" ;;
                    push) runuser -u ${username} -- git -C ${home}/nix-config remote set-url --add --push origin "$url" ;;
                  esac
                done <${seed}/remotes 2>/dev/null || true
              fi

              # agenix decrypted during activation, before the key existed.
              echo "Decrypting secrets."
              /run/current-system/activate || echo "Activation reported errors; see the journal."

              if [ -e ${seed}/id_ed25519 ]; then shred -u ${seed}/id_ed25519; fi
              rm -rf ${seed}
              touch /var/lib/frieren-first-boot
              echo "Done."
            '';
          };
        }
      )
    ];
  };

  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      image = inputs.self.nixosConfigurations.frieren.config;

      disk = import (inputs.nixpkgs + "/nixos/lib/make-disk-image.nix") {
        inherit lib pkgs;
        config = image;
        name = "frieren-asahi";
        format = "raw";
        partitionTableType = "efi";
        copyChannel = false;
        diskSize = "auto";
        bootSize = "512M";
        additionalSpace = "4G";
        memSize = 4096;
      };
    in
    {
      packages = lib.optionalAttrs (system == "aarch64-linux") {
        # The Asahi Installer package: esp/ and root.img in one zip, plus the
        # installer data that describes them. Its package name is relative, so
        # the installer reads it from REPO_BASE/os/ on this Mac (asahi.sh).
        frieren-asahi-image =
          pkgs.runCommand "frieren-asahi-image"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.jq
                pkgs.p7zip
                pkgs.util-linux
              ];
            }
            ''
              disk=$(echo ${disk}/*.img)
              mkdir -p package/esp $out

              sfdisk -J "$disk" > table.json
              read -r espStart espSize < <(jq -r '.partitiontable.partitions[0] | "\(.start) \(.size)"' table.json)
              read -r rootStart rootSize < <(jq -r '.partitiontable.partitions[1] | "\(.start) \(.size)"' table.json)

              dd if="$disk" of=esp.img bs=512 skip="$espStart" count="$espSize" status=none
              dd if="$disk" of=package/root.img bs=512 skip="$rootStart" count="$rootSize" status=none

              7z x -opackage/esp esp.img >/dev/null
              rm -rf package/esp/EFI/nixos/.extra-files

              pkgZip="frieren-asahi-image.zip"
              (cd package && 7z a -tzip -r -mx1 -bso0 "../$pkgZip" ./.)

              jq -n \
                --arg name "NixOS frieren" \
                --arg package "$pkgZip" \
                --argjson espSize "$((espSize * 512))" \
                --argjson rootSize "$((rootSize * 512))" \
                --argjson supported ${lib.escapeShellArg (builtins.toJSON supportedFw)} \
                '{ os_list: [{
                  name: $name,
                  default_os_name: "NixOS",
                  # Not read by the Asahi Installer. asahi.sh only writes the
                  # first-boot seed for an image whose first boot deletes it.
                  frieren_seed: 1,
                  boot_object: "m1n1.bin",
                  next_object: "m1n1/boot.bin",
                  package: $package,
                  supported_fw: $supported,
                  partitions: [
                    { name: "EFI", type: "EFI", size: "\($espSize)B", format: "fat",
                      volume_id: "0x86221808", copy_firmware: true, copy_installer_data: true, source: "esp" },
                    { name: "Root", type: "Linux", size: "\($rootSize)B", image: "root.img", expand: true }
                  ]
                }] }' > installer_data.json

              mv "$pkgZip" installer_data.json $out/
            '';
      };
    };
}

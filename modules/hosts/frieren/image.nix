# The frieren system as an image the Asahi Installer writes into a new
# partition, the same way it writes Fedora's images. The installer creates the
# ESP and the Root partition itself, from the free space it makes by shrinking
# macOS, and leaves the existing partitions alone.
#
# This image is unencrypted: an image has to be a finished filesystem that the
# installer copies, and LUKS needs a passphrase at install time, which an
# image cannot hold. The LUKS layout in disko.nix stays for the other install
# path (frieren-install), which runs from a live environment.
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
in
{
  flake.nixosConfigurations.frieren-image = inputs.nixpkgs.lib.nixosSystem {
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

          # Nothing secret is in the image. On the first boot, on tty1, the
          # user sets a password and pastes the frieren key; agenix can then
          # decrypt on the next boot.
          systemd.services.frieren-first-boot = {
            description = "First-boot setup for frieren: password and key";
            wantedBy = [ "multi-user.target" ];
            before = [ "greetd.service" ];
            unitConfig.ConditionPathExists = "!/var/lib/frieren-first-boot";
            path = [
              pkgs.coreutils
              pkgs.openssh
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
              echo "First boot of frieren. Set the password for ${username}:"
              until /run/wrappers/bin/passwd ${username}; do
                echo "Try again."
              done

              echo "Paste the frieren id_ed25519 key, then press Ctrl-D:"
              install -d -m 700 -o ${username} -g users /home/${username}
              install -d -m 700 -o ${username} -g users /home/${username}/.ssh
              key=$(mktemp)
              cat >"$key"
              install -m 600 -o ${username} -g users "$key" /home/${username}/.ssh/id_ed25519
              ssh-keygen -y -f "$key" >/home/${username}/.ssh/id_ed25519.pub
              chown ${username}:users /home/${username}/.ssh/id_ed25519.pub
              rm -f "$key"

              touch /var/lib/frieren-first-boot
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
      image = inputs.self.nixosConfigurations.frieren-image.config;

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

# modules/system/preservation.nix declares what survives; this declares how the
# root is reset — on every boot @ is deleted and recreated from the read-only
# @-blank snapshot taken once at install time (see the README).
{
  flake.modules.nixos."hosts/frieren" =
    { pkgs, ... }:
    {
      # Preservation bind-mounts state out of /persist, so it must be mounted
      # early rather than as a late fileSystems target.
      fileSystems."/persist".neededForBoot = true;

      # frieren uses a systemd initrd, so the rollback is an initrd service
      # ordered after the LUKS device opens and before the root is mounted.
      boot.initrd.systemd.services.rollback = {
        description = "Rollback btrfs root (@) to a blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "dev-mapper-cryptroot.device" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          btrfs=${pkgs.btrfs-progs}/bin/btrfs
          mkdir -p /mnt
          mount -o subvol=/ /dev/mapper/cryptroot /mnt

          # Clear any nested subvolumes that accumulated under @ first,
          # otherwise the top-level delete refuses.
          $btrfs subvolume list -o /mnt/@ | cut -f9 -d' ' | while read subvol; do
            echo "deleting nested subvolume /$subvol"
            $btrfs subvolume delete "/mnt/$subvol"
          done

          echo "deleting and restoring /@"
          $btrfs subvolume delete /mnt/@
          $btrfs subvolume snapshot /mnt/@-blank /mnt/@

          umount /mnt
        '';
      };

      boot.initrd.systemd.storePaths = [ pkgs.btrfs-progs ];
    };
}

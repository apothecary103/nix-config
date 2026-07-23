{ inputs, ... }:
{
  flake.modules.nixos."hosts/frieren" = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices.disk.root = {
      type = "disk";
      # The LUKS root partition the Asahi installer carved out. Referencing the
      # existing LUKS header UUID keeps the already-installed machine booting as
      # before. For a fresh, destructive disko run point this at the raw
      # partition instead (e.g. /dev/nvme0n1p6 — confirm with `lsblk`), since
      # luksFormat assigns a new UUID.
      device = "/dev/disk/by-uuid/162e3f71-01e3-4f58-8567-1f5748529e66";
      content = {
        type = "luks";
        name = "cryptroot";
        settings.allowDiscards = true;
        content = {
          type = "btrfs";
          subvolumes = {
            "@" = {
              mountpoint = "/";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
            "@nix" = {
              mountpoint = "/nix";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
            "@persist" = {
              mountpoint = "/persist";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
            # No @home subvolume: /home rides on the wiped @ root, so it is
            # ephemeral too. What survives is opt-in via preservation's per-user
            # persist list (modules/system/preservation.nix).
            "@log" = {
              mountpoint = "/var/log";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
            # Fulfils the swap TODO: a dedicated subvolume whose swapfile lands
            # at /swap/swapfile. disko creates it NOCOW and wires swapDevices.
            "@swap" = {
              mountpoint = "/swap";
              swap.swapfile.size = "2G";
            };
          };
        };
      };
    };
  };
}

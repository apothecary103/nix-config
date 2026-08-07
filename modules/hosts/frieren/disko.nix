{ inputs, ... }:
{
  flake.modules.nixos."hosts/frieren" = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices.disk.root = {
      type = "disk";
      # The existing LUKS header UUID from the Asahi installer, so the
      # already-installed machine keeps booting. A fresh destructive disko run
      # wants the raw partition instead, since luksFormat assigns a new UUID.
      device = "/dev/disk/by-uuid/a0c92d69-f406-4dc1-89af-000fc1ac204e";
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
            # No @home subvolume: /home rides on the wiped @ root and what
            # survives is opt-in via modules/system/preservation.nix.
            "@log" = {
              mountpoint = "/var/log";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
            # disko creates the swapfile NOCOW and wires up swapDevices for it.
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

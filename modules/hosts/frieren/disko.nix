{ inputs, ... }:
let
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  flake.modules.nixos."hosts/frieren" = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices.disk.root = {
      type = "disk";
      # frieren-install (./install.nix) luksFormats the Root partition with
      # this UUID, so the same value serves both a fresh install and boot.
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
              inherit mountOptions;
            };
            "@nix" = {
              mountpoint = "/nix";
              inherit mountOptions;
            };
            "@log" = {
              mountpoint = "/var/log";
              inherit mountOptions;
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

{ lib, ... }:

{
  disko.devices = {

    disk = {
      main = {

        type = "disk";
        device = "/dev/nvme0n1";

        content = {

          type = "gpt";

          partitions = {

            ESP = {
              start = "1M";
              size = "477M";
              type = "EF00";

              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };

            nixos = {

              start = "418G";
              size = "43G";

              content = {

                type = "luks";
                name = "cryptroot";

                passwordFile = "/tmp/luks-password";

                content = {

                  type = "btrfs";

                  extraArgs = [
                    "-f"
                  ];

                  subvolumes = {

                    "@root" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                      ];
                    };

                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                      ];
                    };

                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                      ];
                    };

                    "@persist" = {
                      mountpoint = "/persist";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                      ];
                    };

                  };
                };
              };
            };
          };
        };
      };
    };
  };
}

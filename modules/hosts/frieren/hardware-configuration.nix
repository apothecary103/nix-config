# Non-disk hardware settings. The disk layout (LUKS + btrfs + swap) lives in
# disko.nix.
{
  flake.modules.nixos."hosts/frieren" =
    {
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [
        "usb_storage"
        "sdhci_pci"
      ];

      # The EFI system partition doubles as the Asahi m1n1/U-Boot + vendor
      # firmware carrier, so it is deliberately kept out of disko (never
      # reformat it) and mounted here instead.
      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/8622-1808";
        fsType = "vfat";
        options = [
          "fmask=0022"
          "dmask=0022"
        ];
      };

      nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    };
}

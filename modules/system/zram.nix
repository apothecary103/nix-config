{
  flake.modules.nixos.base = {
    zramSwap = {
      enable = true;
      memoryPercent = 100;
      priority = 100;
    };

    # Disk swap is host-specific: frieren's disko config declares an @swap
    # subvolume with a /swap/swapfile and wires up swapDevices for it. zram's
    # priority (100) outranks the swapfile, so the SSD is only touched once zram
    # is full.
    boot.kernel.sysctl = {
      # Tell the kernel to prefer Zram but not be too aggressive with the SSD
      "vm.swappiness" = 100;
      # Helps with "stutter" when memory is tight
      "vm.page-cluster" = 0;
    };
  };
}

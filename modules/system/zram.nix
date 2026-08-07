{
  flake.modules.nixos.base = {
    zramSwap = {
      enable = true;
      memoryPercent = 100;
      priority = 100;
    };

    # zram's priority (100) outranks frieren's /swap/swapfile (disko.nix), so
    # the SSD is only touched once zram is full.
    boot.kernel.sysctl = {
      "vm.swappiness" = 100;
      "vm.page-cluster" = 0;
    };
  };
}

{ ... }:

{
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    priority = 100;
  };

  swapDevices = [
    {
      # TODO: Create the /swap subvolume and point the device to /swap/swapfile
      device = "/var/lib/swapfile"; 
      size = 2 * 1024; # 2GB
      priority = 10; # Low priority: use this ONLY when Zram is full
    }
  ];

  boot.kernel.sysctl = {
    # Tell the kernel to prefer Zram but not be too aggressive with the SSD
    "vm.swappiness" = 100;
    # Helps with "stutter" when memory is tight
    "vm.page-cluster" = 0;
  };
}

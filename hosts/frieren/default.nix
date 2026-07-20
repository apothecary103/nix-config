{
  pkgs,
  inputs,
  username,
  ...
}:

let
  pkgsCfg = import ../../pkgs { inherit inputs; };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/nixos
    inputs.home-manager.nixosModules.home-manager
    inputs.apple-silicon.nixosModules.apple-silicon-support
  ];

  nixpkgs.overlays = pkgsCfg.overlays;

  networking.hostName = "frieren";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [
    "appledrm.show_notch=1"
  ];

  # NOTE: You must have the firmware files extracted on your EFI partition
  hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;

  time.timeZone = "Europe/Vilnius";

  nix.settings.cores = 0; # Use all available cores

  # Cachix
  nix.settings = {
    extra-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };

  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        ControllerMode = "bredr";
      };
    };
  };

  services.blueman.enable = true;

  services.power-profiles-daemon.enable = true;

  programs.fish.enable = true;

  # xdg.portal = {
  #   enable = true;
  #   xdgOpenUsePortal = true;
  #   extraPortals = [
  #     pkgs.xdg-desktop-portal-gnome
  #     pkgs.xdg-desktop-portal-gtk
  #   ];
  #   config = {
  #     common.default = [ "gnome" "gtk" ];
  #     niri.default = [ "gnome" "gtk" ];
  #   };
  # };

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  programs.dconf.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
    priority = 100;
  };

  # Enable Swapfile
  # NOTE: If you are using Btrfs, you cannot just create a swap file anywhere.
  # If you do, Btrfs will try to "snapshot" it, which causes
  # massive performance lag and can even crash the system.
  # Before you run nixos-rebuild switch, you should create a dedicated
  # directory for the swap file and disable Copy-on-Write (CoW) on it manually:
  #
  # 1. Create the directory:
  # `sudo mkdir -p /var/lib/swap`
  # 2. Disable CoW:
  # `sudo chattr +C /var/lib/swap`
  #
  swapDevices = [
    {
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

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "video"
      "input"
    ];
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs username;
      hostname = "frieren";
    };

    users.${username} = {
      imports = pkgsCfg.homeModules ++ [
        ../../home/base
        ../../home/nixos
      ];
    };
  };

  system.stateVersion = "25.11";
}
